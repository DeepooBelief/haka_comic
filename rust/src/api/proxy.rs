use sysproxy::{Result, Sysproxy};

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub fn get_proxy() -> Result<Sysproxy> {
    Sysproxy::get_system_proxy()
}
