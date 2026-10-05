#!/usr/bin/env python3
"""Small Fedora/Linux launcher GUI for TruckNav-Sim."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import tkinter as tk
import webbrowser
from pathlib import Path
from tkinter import messagebox, scrolledtext

ATS_APP_ID = os.environ.get("TRUCKNAV_ATS_APP_ID", "270880")
ETS2_APP_ID = os.environ.get("TRUCKNAV_ETS2_APP_ID", "227300")
TRUCKNAV_URL = os.environ.get("TRUCKNAV_URL", "http://127.0.0.1:3000/")
WINDOW_CLASS = "TruckNavLinuxLauncher"
WINDOW_TITLE = "TruckNav Linux Launcher"
CONFIG_PATH = (
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    / "trucknav-linux-launcher"
    / "config.json"
)

THEMES = {
    "light": {
        "window_bg": "#f4f4f4",
        "panel_bg": "#f4f4f4",
        "text_fg": "#1f2328",
        "muted_fg": "#4f5660",
        "button_bg": "#ffffff",
        "button_fg": "#1f2328",
        "button_active_bg": "#e9eef6",
        "button_active_fg": "#111827",
        "field_bg": "#ffffff",
        "field_fg": "#1f2328",
        "insert_bg": "#1f2328",
        "select_bg": "#b7d7ff",
        "select_fg": "#000000",
    },
    "dark": {
        "window_bg": "#171a21",
        "panel_bg": "#171a21",
        "text_fg": "#f2f5f8",
        "muted_fg": "#b7c0cc",
        "button_bg": "#2a2f3a",
        "button_fg": "#f2f5f8",
        "button_active_bg": "#3a4352",
        "button_active_fg": "#ffffff",
        "field_bg": "#0f131a",
        "field_fg": "#e6edf3",
        "insert_bg": "#e6edf3",
        "select_bg": "#355c9a",
        "select_fg": "#ffffff",
    },
}


def find_repo_root() -> Path:
    env_root = os.environ.get("TRUCKNAV_REPO_ROOT")
    if env_root:
        candidate = Path(env_root).expanduser().resolve()
        if (candidate / "package.json").is_file():
            return candidate

    current = Path(__file__).resolve()
    for parent in [current.parent, *current.parents]:
        if (parent / "package.json").is_file() and (parent / "nuxt.config.ts").is_file():
            return parent

    try:
        git_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        candidate = Path(git_root).resolve()
        if (candidate / "package.json").is_file():
            return candidate
    except (OSError, subprocess.CalledProcessError):
        pass

    messagebox.showerror(
        WINDOW_TITLE,
        "Could not detect the TruckNav-Sim repository root. Set TRUCKNAV_REPO_ROOT and try again.",
    )
    sys.exit(1)


def load_config() -> dict[str, object]:
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as config_file:
            loaded = json.load(config_file)
    except (OSError, json.JSONDecodeError):
        return {}

    if isinstance(loaded, dict):
        return loaded
    return {}


def save_config(config: dict[str, object]) -> None:
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with CONFIG_PATH.open("w", encoding="utf-8") as config_file:
            json.dump(config, config_file, indent=2)
            config_file.write("\n")
    except OSError as exc:
        print(f"Could not save launcher config to {CONFIG_PATH}: {exc}", file=sys.stderr)


REPO_ROOT = find_repo_root()
SCRIPT_DIR = REPO_ROOT / "scripts" / "linux"
ICON_PATH = REPO_ROOT / "assets" / "icon-only.png"


def read_trucknav_version() -> str:
    version_file = REPO_ROOT / "VERSION"
    if version_file.is_file():
        raw = version_file.read_text(encoding="utf-8").strip()
    else:
        raw = ""
        package_file = REPO_ROOT / "package.json"
        if package_file.is_file():
            try:
                package = json.loads(package_file.read_text(encoding="utf-8"))
                raw = str(package.get("version") or "")
            except (OSError, json.JSONDecodeError):
                raw = ""

    if not raw:
        return "dev"

    parts = raw.lstrip("v").split(".")
    if len(parts) == 3 and parts[2] == "0":
        return ".".join(parts[:2])
    return raw.lstrip("v")


class Launcher(tk.Tk):
    def __init__(self) -> None:
        # KDE and other desktop shells can match this class with the
        # desktop file StartupWMClass so the running taskbar entry uses the
        # TruckNav icon instead of Tk's generic X icon.
        super().__init__(className=WINDOW_CLASS)
        self.title(WINDOW_TITLE)
        self.set_window_icon()
        self.geometry("720x620")
        self.minsize(640, 520)
        self.processes: list[subprocess.Popen[str]] = []
        self.config_data = load_config()
        self.active_channel = str(
            self.config_data.get("active_channel")
            or ("stable" if REPO_ROOT.name == "TruckNav-Sim-Fire-Fedora" else "testing")
        )
        self.dark_mode = tk.BooleanVar(value=self.config_data.get("dark_mode") is True)
        self.stop_trucknav_on_close = tk.BooleanVar(value=False)
        self.selected_game = tk.StringVar(
            value=str(self.config_data.get("selected_game") or "ats")
        )
        if self.selected_game.get() not in {"ats", "ets2"}:
            self.selected_game.set("ats")
        self.version = read_trucknav_version()

        heading = tk.Label(self, text=WINDOW_TITLE, font=("Sans", 18, "bold"))
        heading.pack(pady=(14, 4))

        self.version_badge = tk.Label(
            self,
            text=f"{self.version} {self.active_channel.title()}",
            font=("Sans", 10, "bold"),
        )
        self.version_badge.place(relx=1.0, x=-14, y=12, anchor="ne")

        self.subtitle = tk.Label(
            self,
            text="",
            justify="center",
        )
        self.subtitle.pack(pady=(0, 8))
        self.update_game_labels()

        channel_frame = tk.Frame(self)
        channel_frame.pack(fill="x", padx=24, pady=(0, 6))

        tk.Label(
            channel_frame,
            text="Launcher channel:",
            anchor="w",
        ).pack(side="left")

        update_button = tk.Button(
            channel_frame,
            text="Update TruckNav",
            command=lambda: self.run_script(
                "update-trucknav-linux.sh",
                wait=False,
            ),
            padx=12,
        )
        update_button.pack(side="right", padx=(6, 0))

        for channel in ("stable", "testing"):
            repo = self.channel_repo(channel)
            button = tk.Button(
                channel_frame,
                text=channel.title(),
                command=lambda ch=channel: self.switch_channel(ch),
                padx=12,
            )
            if not repo or channel == self.active_channel:
                button.configure(state="disabled")
            button.pack(side="right", padx=(6, 0))

        game_frame = tk.Frame(self)
        game_frame.pack(fill="x", padx=24, pady=(0, 4))

        tk.Label(
            game_frame,
            text="Game:",
            anchor="w",
        ).pack(side="left")

        for game, label in (("ats", "ATS"), ("ets2", "ETS2")):
            tk.Radiobutton(
                game_frame,
                text=label,
                value=game,
                variable=self.selected_game,
                command=self.change_game,
                indicatoron=False,
                padx=14,
            ).pack(side="right", padx=(6, 0))

        button_frame = tk.Frame(self)
        button_frame.pack(fill="x", padx=18)

        buttons = [
            (
                "Launch TruckNav",
                self.launch_trucknav_only,
            ),
            (
                self.game_launch_label(),
                self.launch_selected_game,
            ),
            (
                "Stop TruckNav",
                lambda: self.run_script("stop-trucknav.sh", wait=True),
            ),
            ("Open TruckNav in browser", self.open_browser),
            (
                "Check dependencies/status",
                lambda: self.run_script("check-status.sh", wait=True),
            ),
            ("Install/repair Fedora setup", self.install_fedora),
        ]

        for index, (label, command) in enumerate(buttons):
            button = tk.Button(button_frame, text=label, command=command, height=2)
            button.grid(row=index // 2, column=index % 2, sticky="ew", padx=6, pady=6)
            if index == 1:
                self.launch_game_button = button
        button_frame.columnconfigure(0, weight=1)
        button_frame.columnconfigure(1, weight=1)

        options_frame = tk.Frame(self)
        options_frame.pack(fill="x", padx=24, pady=(4, 0))
        stop_on_close = tk.Checkbutton(
            options_frame,
            text="Stop TruckNav when closing launcher",
            variable=self.stop_trucknav_on_close,
            anchor="w",
        )
        stop_on_close.pack(anchor="w")

        dark_mode_toggle = tk.Checkbutton(
            options_frame,
            text="Dark mode",
            variable=self.dark_mode,
            command=self.toggle_dark_mode,
            anchor="w",
        )
        dark_mode_toggle.pack(anchor="w", pady=(2, 0))

        close_note = tk.Label(
            options_frame,
            text="Closing this launcher does not stop TruckNav unless enabled.",
            anchor="w",
            justify="left",
        )
        close_note.pack(fill="x", pady=(2, 0))

        self.output = scrolledtext.ScrolledText(self, height=18, state="disabled")
        self.output.pack(fill="both", expand=True, padx=18, pady=(8, 14))

        self.apply_theme()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.append_output(
            f"Active channel: {self.active_channel.title()} ({REPO_ROOT})\n"
        )
        self.append_output("Use Check dependencies/status first if this is a new Fedora setup.\n")

    def game_label(self) -> str:
        return "ETS2" if self.selected_game.get() == "ets2" else "ATS"

    def game_app_id(self) -> str:
        return ETS2_APP_ID if self.selected_game.get() == "ets2" else ATS_APP_ID

    def game_launch_label(self) -> str:
        return f"Launch {self.game_label()} + TruckNav together"

    def update_game_labels(self) -> None:
        if hasattr(self, "subtitle"):
            self.subtitle.configure(
                text=(
                    f"Channel: {self.active_channel.title()}\n"
                    f"Repo: {REPO_ROOT}\n"
                    f"{self.game_label()} Steam app id: {self.game_app_id()}"
                )
            )
        if hasattr(self, "launch_game_button"):
            self.launch_game_button.configure(text=self.game_launch_label())

    def change_game(self) -> None:
        self.config_data["selected_game"] = self.selected_game.get()
        save_config(self.config_data)
        self.update_game_labels()
        self.append_output(
            f"Selected game: {self.game_label()} ({self.game_app_id()})\n"
        )

    def launch_trucknav_only(self) -> None:
        self.run_script(
            "launch-trucknav.sh",
            wait=False,
            args=[self.selected_game.get()],
        )

    def launch_selected_game(self) -> None:
        self.run_script(
            "launch-game-trucknav.sh",
            wait=False,
            args=[self.selected_game.get()],
        )

    def channel_repo(self, channel: str) -> Path | None:
        channels = self.config_data.get("channels")
        if not isinstance(channels, dict):
            return None

        raw_path = channels.get(channel)
        if not isinstance(raw_path, str) or not raw_path:
            return None

        candidate = Path(raw_path).expanduser().resolve()
        if not (candidate / "package.json").is_file():
            return None
        return candidate

    def switch_channel(self, channel: str) -> None:
        repo = self.channel_repo(channel)
        if repo is None:
            messagebox.showerror(
                WINDOW_TITLE,
                f"No valid repository is registered for the {channel.title()} channel.",
            )
            return

        if channel == self.active_channel:
            return

        self.config_data["active_channel"] = channel
        save_config(self.config_data)

        wrapper = Path.home() / ".local" / "bin" / "trucknav-linux-launcher"
        self.append_output(
            f"Switching active channel to {channel}: {repo}\n"
        )
        messagebox.showinfo(
            WINDOW_TITLE,
            (
                f"Switching TruckNav Linux to {channel.title()}.\n\n"
                f"{repo}\n\n"
                "The launcher will reopen using that checkout."
            ),
        )

        if wrapper.is_file():
            try:
                subprocess.Popen(
                    [str(wrapper)],
                    env=os.environ.copy(),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError as exc:
                messagebox.showerror(
                    WINDOW_TITLE,
                    f"Channel changed, but the launcher could not be reopened: {exc}",
                )
        else:
            messagebox.showinfo(
                WINDOW_TITLE,
                "Channel changed. Close and reopen TruckNav Linux Launcher.",
            )

        self.destroy()

    def set_window_icon(self) -> None:
        try:
            self.icon_image = tk.PhotoImage(file=ICON_PATH)
            self.iconphoto(True, self.icon_image)
        except (OSError, tk.TclError) as exc:
            print(f"Could not load launcher window icon from {ICON_PATH}: {exc}", file=sys.stderr)

    def current_theme(self) -> dict[str, str]:
        return THEMES["dark" if self.dark_mode.get() else "light"]

    def apply_theme(self) -> None:
        theme = self.current_theme()
        self.configure(bg=theme["window_bg"])
        for child in self.winfo_children():
            self.apply_theme_to_widget(child, theme)

        if hasattr(self, "version_badge"):
            self.version_badge.configure(
                bg=theme["panel_bg"],
                fg=theme["muted_fg"],
            )

    def apply_theme_to_widget(self, widget: tk.Widget, theme: dict[str, str]) -> None:
        if isinstance(widget, tk.Button):
            widget.configure(
                bg=theme["button_bg"],
                fg=theme["button_fg"],
                activebackground=theme["button_active_bg"],
                activeforeground=theme["button_active_fg"],
                highlightbackground=theme["panel_bg"],
            )
        elif isinstance(widget, (tk.Checkbutton, tk.Radiobutton)):
            widget.configure(
                bg=theme["panel_bg"],
                fg=theme["text_fg"],
                activebackground=theme["panel_bg"],
                activeforeground=theme["text_fg"],
                selectcolor=theme["field_bg"],
                highlightbackground=theme["panel_bg"],
            )
        elif isinstance(widget, scrolledtext.ScrolledText):
            widget.configure(
                bg=theme["field_bg"],
                fg=theme["field_fg"],
                insertbackground=theme["insert_bg"],
                selectbackground=theme["select_bg"],
                selectforeground=theme["select_fg"],
                highlightbackground=theme["panel_bg"],
            )
        elif isinstance(widget, tk.Label):
            widget.configure(bg=theme["panel_bg"], fg=theme["text_fg"])
        elif isinstance(widget, tk.Frame):
            widget.configure(bg=theme["panel_bg"], highlightbackground=theme["panel_bg"])

        for child in widget.winfo_children():
            self.apply_theme_to_widget(child, theme)

    def toggle_dark_mode(self) -> None:
        self.apply_theme()
        self.config_data["dark_mode"] = self.dark_mode.get()
        save_config(self.config_data)

    def env(self) -> dict[str, str]:
        env = os.environ.copy()
        env["TRUCKNAV_REPO_ROOT"] = str(REPO_ROOT)
        env["TRUCKNAV_ATS_APP_ID"] = ATS_APP_ID
        env["TRUCKNAV_ETS2_APP_ID"] = ETS2_APP_ID
        env["TRUCKNAV_GAME"] = self.selected_game.get()
        env["TRUCKNAV_URL"] = TRUCKNAV_URL
        return env

    def append_output(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def run_script(
        self,
        script_name: str,
        wait: bool,
        args: list[str] | None = None,
    ) -> None:
        script = SCRIPT_DIR / script_name
        if not script.is_file():
            messagebox.showerror("Missing script", f"Could not find {script}")
            return

        command = ["bash", str(script), *(args or [])]
        self.append_output("\n$ " + " ".join(command) + "\n")
        try:
            if wait:
                result = subprocess.run(
                    command,
                    cwd=REPO_ROOT,
                    env=self.env(),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                self.append_output(result.stdout or "")
                if result.returncode != 0:
                    messagebox.showerror(
                        "TruckNav command failed",
                        f"{script_name} exited with status {result.returncode}. See output for details.",
                    )
            else:
                process = subprocess.Popen(
                    command,
                    cwd=REPO_ROOT,
                    env=self.env(),
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )
                self.track_process(process)
        except FileNotFoundError as exc:
            messagebox.showerror("Command not found", str(exc))
        except OSError as exc:
            messagebox.showerror("Could not run command", str(exc))

    def install_fedora(self) -> None:
        installer = REPO_ROOT / "scripts" / "install-fedora.sh"
        if not installer.is_file():
            messagebox.showerror("Missing installer", f"Could not find {installer}")
            return
        self.append_output(f"\n$ {installer}\n")
        process = subprocess.Popen(
            [str(installer)],
            cwd=REPO_ROOT,
            env=self.env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.track_process(process)

    def track_process(self, process: subprocess.Popen[str]) -> None:
        self.processes.append(process)
        thread = threading.Thread(target=self.drain_process, args=(process,), daemon=True)
        thread.start()

    def drain_process(self, process: subprocess.Popen[str]) -> None:
        if process.stdout is not None:
            for line in process.stdout:
                self.after(0, self.append_output, line)
        return_code = process.wait()
        self.after(0, self.process_finished, process, return_code)

    def process_finished(self, process: subprocess.Popen[str], return_code: int) -> None:
        self.append_output(f"Command exited with status {return_code}.\n")
        if process in self.processes:
            self.processes.remove(process)

    def open_browser(self) -> None:
        self.append_output(f"Opening {TRUCKNAV_URL}\n")
        webbrowser.open(TRUCKNAV_URL)

    def stop_trucknav_before_close(self) -> None:
        stop_script = SCRIPT_DIR / "stop-trucknav.sh"
        if not stop_script.is_file():
            messagebox.showerror("Missing script", f"Could not find {stop_script}")
            return

        self.append_output("\nClosing launcher: stopping TruckNav web app and telemetry only. Steam/ATS will not be stopped.\n")
        result = subprocess.run(
            [str(stop_script)],
            cwd=REPO_ROOT,
            env=self.env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.append_output(result.stdout or "")
        if result.returncode != 0:
            messagebox.showerror(
                "TruckNav stop failed",
                f"stop-trucknav.sh exited with status {result.returncode}. See output for details.",
            )

    def on_close(self) -> None:
        if self.stop_trucknav_on_close.get():
            self.stop_trucknav_before_close()
        else:
            message = "Closing launcher: leaving TruckNav running. Use Stop TruckNav to stop the web app and telemetry.\n"
            self.append_output(message)
            print(message, end="")

        for process in list(self.processes):
            if process.poll() is None:
                process.terminate()
        self.destroy()


if __name__ == "__main__":
    Launcher().mainloop()
