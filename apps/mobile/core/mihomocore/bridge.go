// Package mihomocore 将 mihomo 内核嵌入 Android 宿主进程（gomobile 绑定）。
//
// 设计参考 FlClash 的挂点思路（架构参考，未复制其 GPL 代码）：
//   - TUN fd 由 Kotlin 侧 VpnService 建立后传入，sing_tun 以
//     FileDescriptor 模式接管（AutoRoute=false，路由由 VpnService.Builder 完成）
//   - dialer.DefaultSocketHook 实现 protect（接口绑定）
//   - process.DefaultPackageNameResolver 实现按应用分流规则
//   - log.Subscribe 捕获内核日志回调给宿主
package mihomocore

import (
	"fmt"
	"net"
	"net/netip"
	"os"
	"strings"
	"sync"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// EventCallback 宿主回调（由 Kotlin VpnService 实现）。
type EventCallback interface {
	// OnLog 内核日志（level: debug/info/warning/error）
	OnLog(level string, message string)
	// Protect 请求将 fd 绑定到默认网络（绕过 TUN）；返回是否成功
	Protect(fd int32) bool
	// ResolveProcess 返回连接所属包名（按应用分流）；查不到返回空串。
	// uid < 0 表示宿主无法获取（Android 10 以下），由宿主自行决定降级策略。
	ResolveProcess(protocol int32, source string, target string, uid int32) string
}

var (
	mutex           sync.Mutex
	running         bool
	serviceCallback EventCallback
	tunCallback     EventCallback
	tunListener     *sing_tun.Listener
	logStop         chan struct{}
)

// Setup 设置 mihomo 主目录（geodata/cache.db 等落盘位置）。须最先调用。
func Setup(homeDir string) error {
	if homeDir == "" {
		return fmt.Errorf("homeDir is empty")
	}
	if err := os.MkdirAll(homeDir, 0o755); err != nil {
		return fmt.Errorf("create home dir: %w", err)
	}
	constant.SetHomeDir(homeDir)
	return nil
}

// StartService 解析配置并启动 mihomo（含入站监听）。配置中不应包含 tun 段
// （Android 的 tun 由 StartTun 以外部 fd 方式建立）。
func StartService(configContent string, cb EventCallback) error {
	mutex.Lock()
	defer mutex.Unlock()
	if cb == nil {
		return fmt.Errorf("callback is nil")
	}
	if running {
		return fmt.Errorf("mihomo is already running")
	}
	serviceCallback = cb
	cfg, err := executor.ParseWithBytes([]byte(configContent))
	if err != nil {
		serviceCallback = nil
		return fmt.Errorf("解析配置失败: %w", err)
	}
	executor.ApplyConfig(cfg, true)
	running = true
	startLogPump(cb)
	cb.OnLog("info", "mihomo 内核已启动")
	return nil
}

// StopService 停止 mihomo（自动先停 tun）。
func StopService() error {
	mutex.Lock()
	defer mutex.Unlock()
	if !running {
		return nil
	}
	stopTunLocked()
	stopLogPump()
	executor.Shutdown()
	running = false
	if serviceCallback != nil {
		serviceCallback.OnLog("info", "mihomo 内核已停止")
	}
	serviceCallback = nil
	return nil
}

// IsRunning 返回内核是否运行中。
func IsRunning() bool {
	mutex.Lock()
	defer mutex.Unlock()
	return running
}

// StartTun 以外部 fd 建立 TUN 监听并安装 protect/进程解析钩子。
// address 为逗号分隔的 tun 地址段（IPv4/IPv6），dns 为逗号分隔的 DNS 劫持地址。
// stack: gvisor | system | mixed（空/未知时回退 system）。
func StartTun(fd int32, stack string, address string, dns string, cb EventCallback) error {
	mutex.Lock()
	defer mutex.Unlock()
	if fd == 0 {
		return fmt.Errorf("无效的 tun fd")
	}
	if !running {
		return fmt.Errorf("mihomo 未运行")
	}
	if tunListener != nil {
		return nil
	}

	var prefix4, prefix6 []netip.Prefix
	for _, a := range strings.Split(address, ",") {
		a = strings.TrimSpace(a)
		if a == "" {
			continue
		}
		prefix, err := netip.ParsePrefix(a)
		if err != nil {
			return fmt.Errorf("tun 地址错误: %w", err)
		}
		if prefix.Addr().Is4() {
			prefix4 = append(prefix4, prefix)
		} else {
			prefix6 = append(prefix6, prefix)
		}
	}
	var dnsHijack []string
	for _, d := range strings.Split(dns, ",") {
		d = strings.TrimSpace(d)
		if d == "" {
			continue
		}
		dnsHijack = append(dnsHijack, net.JoinHostPort(d, "53"))
	}

	stackType, ok := constant.StackTypeMapping[strings.ToLower(stack)]
	if !ok {
		stackType = constant.TunSystem
	}

	tunCallback = cb
	listener, err := sing_tun.New(LC.Tun{
		Enable:              true,
		Device:              "smgui",
		Stack:               stackType,
		DNSHijack:           dnsHijack,
		AutoRoute:           false,
		AutoDetectInterface: false,
		Inet4Address:        prefix4,
		Inet6Address:        prefix6,
		MTU:                 9000,
		FileDescriptor:      int(fd),
	}, tunnel.Tunnel)
	if err != nil {
		tunCallback = nil
		return fmt.Errorf("tun 启动失败: %w", err)
	}
	tunListener = listener
	installHooks()
	return nil
}

// StopTun 停止 TUN 监听并卸载钩子。
func StopTun() error {
	mutex.Lock()
	defer mutex.Unlock()
	stopTunLocked()
	return nil
}

func stopTunLocked() {
	if tunListener == nil {
		tunCallback = nil
		return
	}
	uninstallHooks()
	_ = tunListener.Close()
	tunListener = nil
	tunCallback = nil
}

func installHooks() {
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		cb := activeCallback()
		if cb == nil {
			return nil
		}
		return conn.Control(func(fdPtr uintptr) {
			if !cb.Protect(int32(fdPtr)) {
				log.Warnln("[bridge] protect fd failed: %d", fdPtr)
			}
		})
	}
	process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
		cb := activeCallback()
		if cb == nil {
			return "", nil
		}
		src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
		if src == nil || dst == nil {
			return "", process.ErrInvalidNetwork
		}
		var protocol int32 = syscall.IPPROTO_TCP
		switch src.Network() {
		case "udp", "udp4", "udp6":
			protocol = syscall.IPPROTO_UDP
		}
		return cb.ResolveProcess(protocol, src.String(), dst.String(), -1), nil
	}
}

func uninstallHooks() {
	dialer.DefaultSocketHook = nil
	process.DefaultPackageNameResolver = nil
}

func activeCallback() EventCallback {
	if tunCallback != nil {
		return tunCallback
	}
	return serviceCallback
}

func startLogPump(cb EventCallback) {
	stopLogPump()
	logStop = make(chan struct{})
	sub := log.Subscribe() // observable.Subscription[Event] 即 <-chan Event
	go func() {
		for {
			select {
			case <-logStop:
				log.UnSubscribe(sub)
				return
			case event, ok := <-sub:
				if !ok {
					log.UnSubscribe(sub)
					return
				}
				if c := activeCallback(); c != nil {
					c.OnLog(event.LogLevel.String(), event.Payload)
				}
			}
		}
	}()
}

func stopLogPump() {
	if logStop != nil {
		close(logStop)
		logStop = nil
	}
}

// Version 返回嵌入的 mihomo 版本。
func Version() string {
	return constant.Version
}
