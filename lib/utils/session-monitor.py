#!/usr/bin/env python3
"""
RDP Session Resource Monitoring Utility
Tracks per-session memory usage and validates resource consumption targets

Usage:
    python3 session-monitor.py [--json] [--threshold PERCENT]

Options:
    --json              Output in JSON format
    --threshold PERCENT Warn if memory usage exceeds threshold (default: 75)

Exit codes:
    0 - All sessions within resource limits
    1 - One or more sessions exceeding thresholds
    2 - Error executing command
"""

import argparse
import json
import subprocess
import sys
from typing import Any, Dict, List


class SessionMonitor:
    """Monitor and report on RDP session resource usage"""

    # Performance target: 3 concurrent sessions within 4GB RAM (NFR-004)
    # Expected: ~1.3GB per active session, 1GB system buffer
    MAX_MEMORY_MB = 4096  # 4GB total system RAM
    TARGET_BUFFER_MB = 1024  # 1GB buffer for system
    TARGET_SESSIONS = 3
    EXPECTED_PER_SESSION_MB = (
        MAX_MEMORY_MB - TARGET_BUFFER_MB
    ) / TARGET_SESSIONS  # ~1024MB

    def __init__(self) -> None:
        self.sessions: List[Dict[str, Any]] = []

    def get_active_sessions(self) -> List[Dict[str, Any]]:
        """
        Get list of active xrdp sessions with resource usage

        Returns:
            List of session dicts with display, user, pid, memory_mb
        """
        sessions = []

        try:
            # Get xrdp session processes
            cmd = ["ps", "aux"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            for line in result.stdout.splitlines():
                # Look for Xorg processes spawned by xrdp (display :10, :11, :12, etc.)
                if "Xorg" in line and ":1" in line:
                    parts = line.split()
                    if len(parts) < 11:
                        continue

                    user = parts[0]
                    pid = parts[1]
                    mem_percent = float(parts[3])

                    # Extract display number from command
                    display = None
                    for part in parts[10:]:
                        if part.startswith(":") and part[1:].isdigit():
                            display = part
                            break

                    if not display:
                        continue

                    # Calculate memory in MB
                    # mem_percent is % of total system RAM
                    memory_mb = (mem_percent / 100.0) * self.MAX_MEMORY_MB

                    sessions.append(
                        {
                            "display": display,
                            "user": user,
                            "pid": int(pid),
                            "memory_mb": round(memory_mb, 2),
                            "memory_percent": mem_percent,
                        }
                    )

            return sessions

        except subprocess.CalledProcessError as e:
            print(f"Error getting process list: {e}", file=sys.stderr)
            return []

    def get_system_memory(self) -> Dict[str, float]:
        """
        Get overall system memory statistics

        Returns:
            Dict with total_mb, used_mb, free_mb, available_mb
        """
        try:
            cmd = ["free", "-m"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            lines = result.stdout.splitlines()
            if len(lines) < 2:
                return {}

            # Parse 'Mem:' line
            mem_line = lines[1].split()
            if len(mem_line) < 7:
                return {}

            return {
                "total_mb": float(mem_line[1]),
                "used_mb": float(mem_line[2]),
                "free_mb": float(mem_line[3]),
                "available_mb": float(mem_line[6]),
            }

        except (subprocess.CalledProcessError, ValueError, IndexError) as e:
            print(f"Error getting memory stats: {e}", file=sys.stderr)
            return {}

    def check_thresholds(self, threshold_percent: int = 75) -> bool:
        """
        Check if resource usage is within acceptable thresholds

        Args:
            threshold_percent: Warn if memory usage exceeds this percentage

        Returns:
            True if all checks pass, False if any threshold exceeded
        """
        system_mem = self.get_system_memory()
        if not system_mem:
            return False

        # Check overall system memory usage
        used_percent = (system_mem["used_mb"] / system_mem["total_mb"]) * 100
        if used_percent > threshold_percent:
            print(
                f"WARNING: System memory usage {used_percent:.1f}% "
                f"exceeds threshold {threshold_percent}%",
                file=sys.stderr,
            )
            return False

        # Check per-session memory usage
        sessions = self.get_active_sessions()
        for session in sessions:
            mem_mb = float(session["memory_mb"])
            if mem_mb > self.EXPECTED_PER_SESSION_MB * 1.5:  # 50% over expected
                expected_mb = self.EXPECTED_PER_SESSION_MB
                print(
                    f"WARNING: Session {session['display']} using {session['memory_mb']}MB "
                    f"(expected ~{expected_mb:.0f}MB)",
                    file=sys.stderr,
                )
                return False

        return True

    def generate_report(self, output_json: bool = False, threshold: int = 75) -> str:
        """
        Generate monitoring report

        Args:
            output_json: Output in JSON format
            threshold: Memory threshold percentage for warnings

        Returns:
            Report string (JSON or human-readable)
        """
        system_mem = self.get_system_memory()
        sessions = self.get_active_sessions()
        thresholds_ok = self.check_thresholds(threshold)

        if output_json:
            report = {
                "system_memory": system_mem,
                "active_sessions": sessions,
                "session_count": len(sessions),
                "thresholds_ok": thresholds_ok,
                "targets": {
                    "max_sessions": self.TARGET_SESSIONS,
                    "expected_per_session_mb": round(self.EXPECTED_PER_SESSION_MB, 2),
                    "buffer_mb": self.TARGET_BUFFER_MB,
                },
            }
            return json.dumps(report, indent=2)

        # Human-readable format
        lines = []
        lines.append("=" * 70)
        lines.append("RDP Session Resource Monitor")
        lines.append("=" * 70)
        lines.append("")

        # System memory
        if system_mem:
            used_pct = (system_mem["used_mb"] / system_mem["total_mb"]) * 100
            lines.append("System Memory:")
            lines.append(f"  Total:     {system_mem['total_mb']:.0f} MB")
            lines.append(
                f"  Used:      {system_mem['used_mb']:.0f} MB ({used_pct:.1f}%)"
            )
            lines.append(f"  Available: {system_mem['available_mb']:.0f} MB")
            lines.append("")

        # Active sessions
        lines.append(f"Active RDP Sessions: {len(sessions)}")
        if sessions:
            lines.append("")
            lines.append(
                f"{'Display':<10} {'User':<15} {'PID':<8} {'Memory (MB)':<12} {'% RAM':<8}"
            )
            lines.append("-" * 70)
            for session in sessions:
                lines.append(
                    f"{session['display']:<10} "
                    f"{session['user']:<15} "
                    f"{session['pid']:<8} "
                    f"{session['memory_mb']:<12.2f} "
                    f"{session['memory_percent']:<8.2f}"
                )
        lines.append("")

        # Performance targets
        lines.append("Performance Targets (NFR-004):")
        lines.append(f"  Max Concurrent Sessions: {self.TARGET_SESSIONS}")
        lines.append(
            f"  Expected per Session:    ~{self.EXPECTED_PER_SESSION_MB:.0f} MB"
        )
        lines.append(f"  System Buffer:           {self.TARGET_BUFFER_MB} MB")
        lines.append("")

        # Status
        if thresholds_ok:
            lines.append("Status: ✓ All resource usage within acceptable limits")
        else:
            lines.append("Status: ✗ WARNING - Resource usage exceeds thresholds")

        lines.append("=" * 70)

        return "\n".join(lines)


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Monitor RDP session resource usage")
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    parser.add_argument(
        "--threshold",
        type=int,
        default=75,
        help="Memory threshold percentage for warnings (default: 75)",
    )

    args = parser.parse_args()

    monitor = SessionMonitor()
    report = monitor.generate_report(output_json=args.json, threshold=args.threshold)

    print(report)

    # Exit with appropriate code
    if not monitor.check_thresholds(args.threshold):
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
