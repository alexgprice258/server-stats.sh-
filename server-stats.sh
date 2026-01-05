#!/usr/bin/env bash
set -euo pipefail

hr() { printf '%s\n' "------------------------------------------------------------"; }

bytes_to_human() {
  local b="$1"
  local kib=$((1024))
  local mib=$((1024*1024))
  local gib=$((1024*1024*1024))
  if (( b >= gib )); then
    awk -v b="$b" 'BEGIN{printf "%.2f GiB", b/1024/1024/1024}'
  elif (( b >= mib )); then
    awk -v b="$b" 'BEGIN{printf "%.2f MiB", b/1024/1024}'
  elif (( b >= kib )); then
    awk -v b="$b" 'BEGIN{printf "%.2f KiB", b/1024}'
  else
    printf "%d B" "$b"
  fi
}

get_cpu_usage_percent() {
  local cpu user nice system idle iowait irq softirq steal guest guest_nice
  local idle1 total1 idle2 total2

  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  idle1=$((idle + iowait))
  total1=$((user + nice + system + idle + iowait + irq + softirq + steal))

  sleep 0.2

  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  idle2=$((idle + iowait))
  total2=$((user + nice + system + idle + iowait + irq + softirq + steal))

  local totald=$((total2 - total1))
  local idled=$((idle2 - idle1))

  if (( totald == 0 )); then
    echo "0.0"
    return
  fi

  awk -v totald="$totald" -v idled="$idled" 'BEGIN{
    usage=(totald-idled)*100/totald;
    printf "%.1f", usage
  }'
}

get_mem_stats() {
  local mem_total_kb mem_available_kb
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  mem_available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

  local total_b=$((mem_total_kb * 1024))
  local avail_b=$((mem_available_kb * 1024))
  local used_b=$((total_b - avail_b))

  local used_pct
  used_pct=$(awk -v u="$used_b" -v t="$total_b" 'BEGIN{printf "%.1f", (u*100)/t}')

  echo "$total_b $used_b $avail_b $used_pct"
}

get_disk_stats_root() {
  local line
  line=$(df -B1 / | tail -n 1)
  local total used avail usepct mount
  read -r _ total used avail usepct mount <<<"$line"
  usepct=${usepct%\%}
  echo "$used $avail $usepct"
}

top5_cpu() { ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6; }
top5_mem() { ps -eo pid,comm,%mem --sort=-%mem | head -n 6; }

os_version() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${PRETTY_NAME:-Unknown OS}"
  else
    uname -sr
  fi
}

uptime_pretty() { uptime -p 2>/dev/null || true; }
load_avg() { awk '{print $1" "$2" "$3}' /proc/loadavg; }
logged_in_users() { who 2>/dev/null | wc -l | tr -d ' ' || echo "?"; }

echo "Server Performance Stats"
hr
echo "OS: $(os_version)"
echo "Uptime: $(uptime_pretty)"
echo "Load average (1m 5m 15m): $(load_avg)"
echo "Logged-in users: $(logged_in_users)"
hr

cpu_usage="$(get_cpu_usage_percent)"
echo "Total CPU usage: ${cpu_usage}%"
hr

read -r mem_total mem_used mem_free mem_used_pct < <(get_mem_stats)
echo "Total memory usage:"
echo "  Used: $(bytes_to_human "$mem_used")"
echo "  Free(available): $(bytes_to_human "$mem_free")"
echo "  Total: $(bytes_to_human "$mem_total")"
echo "  Used %: ${mem_used_pct}%"
hr

read -r disk_used disk_free disk_used_pct < <(get_disk_stats_root)
echo "Total disk usage (for /):"
echo "  Used: $(bytes_to_human "$disk_used")"
echo "  Free: $(bytes_to_human "$disk_free")"
echo "  Used %: ${disk_used_pct}%"
hr

echo "Top 5 processes by CPU usage:"
top5_cpu
hr

echo "Top 5 processes by memory usage:"
top5_mem
hr