#!/usr/bin/env python3
"""
clack_ui.py - Modern @clack/prompts aesthetic engine for OMNI / UBAT
====================================================================
Provides timeline rails, milestone diamonds, status cards,
and clean developer CLI layouts for console scripts.
"""

import sys
import re

# Ensure console supports UTF-8 box characters without charmap errors
try:
    if sys.stdout and hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ANSI Color Codes
C_RESET  = "\033[0m"
C_BOLD   = "\033[1m"
C_DIM    = "\033[90m"
C_CYAN   = "\033[36m"
C_GREEN  = "\033[32m"
C_YELLOW = "\033[33m"
C_WHITE  = "\033[97m"

RAIL = f"{C_DIM}\u2502{C_RESET}"


def strip_ansi(text: str) -> str:
    """Removes ANSI escape codes for accurate width calculations."""
    return re.sub(r'\x1b\[[0-9;]*m', '', text)


def start(title: str = "") -> None:
    """Starts the timeline with top bracket."""
    print(f"{C_CYAN}\u250c{C_RESET}   {C_BOLD}{C_WHITE}{title}{C_RESET}")
    print(RAIL)


def step(message: str) -> None:
    """Prints a diamond milestone step."""
    print(f"{C_CYAN}\u25c7{C_RESET}  {message}")
    print(RAIL)


def success(message: str) -> None:
    """Prints a green checkmark success step."""
    print(f"{C_GREEN}\u2713{C_RESET}  {message}")
    print(RAIL)


def card(title: str, lines: list, width: int = 54) -> None:
    """Renders a modern hybrid-rail card with rounded corners."""
    padding = width - len(title) - 4
    if padding < 2:
        padding = 2
    top_line = f"{C_DIM}\u2500{C_RESET}" * padding
    print(f"{C_CYAN}\u25c7{C_RESET}  {C_BOLD}{title}{C_RESET} {top_line}{C_DIM}\u256e{C_RESET}")
    print(f"{RAIL}  {' ' * (width - 1)}{C_DIM}\u2502{C_RESET}")

    for line in lines:
        raw_len = len(strip_ansi(line))
        pad_spaces = " " * max(0, width - raw_len - 1)
        print(f"{RAIL}  {line}{pad_spaces}{C_DIM}\u2502{C_RESET}")

    print(f"{RAIL}  {' ' * (width - 1)}{C_DIM}\u2502{C_RESET}")
    bottom_line = f"{C_DIM}\u2500{C_RESET}" * (width + 1)
    print(f"{C_DIM}\u251c{bottom_line}\u256f{C_RESET}")
    print(RAIL)


def table_card(title: str, headers: list, rows: list, col_widths: list, width: int = 54) -> None:
    """Renders a multi-column data grid inside a hybrid card."""
    padding = width - len(title) - 4
    if padding < 2:
        padding = 2
    top_line = f"{C_DIM}\u2500{C_RESET}" * padding
    print(f"{C_CYAN}\u25c7{C_RESET}  {C_BOLD}{title}{C_RESET} {top_line}{C_DIM}\u256e{C_RESET}")
    print(f"{RAIL}  {' ' * (width - 1)}{C_DIM}\u2502{C_RESET}")

    h_str = "  ".join(f"{C_DIM}{h:<{col_widths[i]}}{C_RESET}" for i, h in enumerate(headers))
    print(f"{RAIL}    {h_str}    {C_DIM}\u2502{C_RESET}")

    for row in rows:
        r_str = "  ".join(f"{row[i]:<{col_widths[i]}}" for i in range(len(row)))
        print(f"{RAIL}    {r_str}    {C_DIM}\u2502{C_RESET}")

    print(f"{RAIL}  {' ' * (width - 1)}{C_DIM}\u2502{C_RESET}")
    bottom_line = f"{C_DIM}\u2500{C_RESET}" * (width + 1)
    print(f"{C_DIM}\u251c{bottom_line}\u256f{C_RESET}")
    print(RAIL)


def finish(message: str = "Done!") -> None:
    """Terminates the timeline cleanly."""
    print(f"{C_CYAN}\u2514{C_RESET}  {C_GREEN}{message}{C_RESET}\n")
