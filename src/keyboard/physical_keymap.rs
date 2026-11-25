use std::collections::HashMap;

// The profile uses decimal USB HID keyboard usages. Cache the conversion to
// peer-native scan codes, including macOS keycode 0 (the A key).
#[derive(Default)]
pub(crate) struct KeyMap {
    profile: String,
    iso: bool,
    targets: HashMap<u32, u32>,
    held: HashMap<u32, u32>,
}

impl KeyMap {
    fn configure(&mut self, profile: &str, iso: bool, native_code: impl Fn(u16) -> Option<u32>) {
        if self.profile == profile && self.iso == iso {
            return;
        }
        self.iso = iso;
        self.profile.clear();
        self.profile.push_str(profile);
        self.targets.clear();
        for rule in profile.split_whitespace() {
            let Some((from, to)) = rule.split_once('=') else {
                continue;
            };
            let code = |s: &str| s.parse::<u16>().ok().and_then(&native_code);
            if let (Some(from), Some(to)) = (code(from), code(to)) {
                self.targets.insert(from, to);
            }
        }
    }

    fn resolve(&mut self, source: u32, fallback: u32, down: bool) -> Option<u32> {
        if self.targets.is_empty() && self.held.is_empty() {
            return Some(fallback);
        }
        let target = self.targets.get(&source).copied().unwrap_or(fallback);
        if down {
            if let Some(&repeat) = self.held.get(&source) {
                return Some(repeat);
            }
            let already_down = self.held.values().any(|&code| code == target);
            self.held.insert(source, target);
            (!already_down).then_some(target)
        } else {
            // A profile may have changed while the source key was down.
            let released = self.held.remove(&source).unwrap_or(fallback);
            (!self.held.values().any(|&code| code == released)).then_some(released)
        }
    }

    pub(super) fn release_all(&mut self) {
        self.held.clear();
    }

    fn take_pressed_targets(&mut self) -> Vec<u32> {
        let mut keys: Vec<_> = self.held.drain().map(|(_, target)| target).collect();
        keys.sort_unstable();
        keys.dedup();
        keys
    }
}

#[cfg(all(feature = "flutter", any(windows, target_os = "macos")))]
impl<T: super::InvokeUiSession> super::Session<T> {
    pub(super) fn release_mapped_keys(&self) {
        use super::{Data, Interface, KeyEvent, KeyboardMode, Message};
        let targets = self.physical_keymap.lock().unwrap().take_pressed_targets();
        for target in targets {
            let mut release = KeyEvent::new();
            release.mode = KeyboardMode::Map.into();
            release.set_chr(target);
            let mut message = Message::new();
            message.set_key_event(release);
            self.send(Data::Message(message));
        }
    }

    pub(super) fn apply_physical_keymap(
        &self,
        source: &super::KeyEvent,
        outgoing: &mut super::KeyEvent,
    ) -> bool {
        use base::{
            config::keys,
            message_proto::{key_event, KeyboardMode},
        };
        if source.mode.enum_value() != Ok(KeyboardMode::Map) {
            return true;
        }
        let Some(key_event::Union::Chr(code)) = source.union else {
            return true;
        };
        let lc = self.lc.read().unwrap();
        #[cfg(windows)]
        let (platform, option) = ("Mac OS", keys::OPTION_KEYMAP_WINDOWS_TO_MAC);
        #[cfg(target_os = "macos")]
        let (platform, option) = ("Windows", keys::OPTION_KEYMAP_MAC_TO_WINDOWS);
        if lc.info.platform != platform {
            return true;
        }
        let mut map = self.physical_keymap.lock().unwrap();
        let profile = lc.options.get(option).map_or("", String::as_str);
        if profile.is_empty() && map.held.is_empty() {
            return true;
        }
        #[cfg(windows)]
        let iso =
            !profile.is_empty() && hbb_common::config::LocalConfig::get_kb_layout_type() == "ISO";
        #[cfg(target_os = "macos")]
        let iso = false;
        map.configure(profile, iso, |usage| {
            #[cfg(windows)]
            if iso {
                rdev::usb_hid_code_to_macos_iso_code(usage.into())
            } else {
                rdev::usb_hid_code_to_macos_code(usage.into())
            }
            #[cfg(target_os = "macos")]
            {
                rdev::usb_hid_code_to_win_scancode(usage.into()).map(u32::from)
            }
        });
        if let Some(target) = map.resolve(code, outgoing.chr(), source.down) {
            outgoing.set_chr(target);
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::KeyMap;

    #[test]
    fn swaps_are_simultaneous_and_support_keycode_zero() {
        let mut map = KeyMap::default();
        let native = |usage| match usage {
            4 => Some(0),
            5 => Some(11),
            _ => None,
        };
        map.configure("4=5 5=4", false, native);
        for down in [true, false] {
            assert_eq!(map.resolve(0, 0, down), Some(11));
            assert_eq!(map.resolve(11, 11, down), Some(0));
            assert_eq!(map.resolve(56, 59, down), Some(59));
        }
    }

    #[test]
    fn shared_target_stays_down_until_both_sources_are_released() {
        let mut map = KeyMap::default();
        map.configure("224=227", false, |u| Some(u.into()));
        assert_eq!(map.resolve(224, 224, true), Some(227));
        assert_eq!(map.resolve(227, 227, true), None);
        map.configure("", false, |u| Some(u.into()));
        assert_eq!(map.resolve(224, 224, false), None);
        assert_eq!(map.resolve(227, 227, false), Some(227));
        assert_eq!(map.resolve(224, 224, true), Some(224));
    }

    #[test]
    fn a_mode_change_releases_each_target_once_and_reconnect_starts_clean() {
        let mut map = KeyMap::default();
        map.configure("224=227", false, |u| Some(u.into()));
        assert_eq!(map.resolve(224, 224, true), Some(227));
        assert_eq!(map.resolve(227, 227, true), None);
        assert_eq!(map.take_pressed_targets(), vec![227]);
        assert_eq!(map.resolve(227, 227, true), Some(227));
        map.release_all();
        assert_eq!(map.resolve(224, 224, true), Some(227));
    }
}
