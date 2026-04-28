use sysproxy::Result;

#[derive(Debug, Default, Clone)]
pub struct SystemProxy {
    pub enable: bool,
    pub host: String,
    pub port: u16,
    pub bypass: String,
}

impl From<sysproxy::Sysproxy> for SystemProxy {
    fn from(value: sysproxy::Sysproxy) -> Self {
        Self {
            enable: value.enable,
            host: value.host,
            port: value.port,
            bypass: value.bypass,
        }
    }
}

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub fn get_proxy() -> Result<SystemProxy> {
    Ok(sysproxy::Sysproxy::get_system_proxy()?.into())
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
pub fn get_proxy() -> Result<SystemProxy> {
    Ok(SystemProxy::default())
}
