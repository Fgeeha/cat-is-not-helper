// Не открывать консольное окно на Windows в релизе.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    cat_is_not_helper_lib::run()
}
