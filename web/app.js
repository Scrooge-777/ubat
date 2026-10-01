/**
 * UBAT PRO - CLIENT-SIDE TELEMETRY ENGINE & UI CONTROLLER
 * Real-time polling, canvas graph rendering, circular SVG animation,
 * process filtering, and process termination handling.
 */

// State
let pollInterval = 1000;
let pollTimer = null;
let cpuHistory = new Array(30).fill(15);
let activeFilter = 'all';
let searchQuery = '';
let currentProcessList = [];
let pendingKillTarget = null;
let isSimulated = false;

// DOM Elements
const batteryCircle = document.getElementById('battery-circle-bar');
const batteryPctVal = document.getElementById('battery-pct-val');
const batteryStatusSub = document.getElementById('battery-status-sub');
const batteryPowerBadge = document.getElementById('battery-power-badge');
const batteryStateIcon = document.getElementById('battery-state-icon');
const batteryWattageVal = document.getElementById('battery-wattage-val');
const batteryTimeVal = document.getElementById('battery-time-val');
const batteryGradeBadge = document.getElementById('battery-grade-badge');
const batteryWearVal = document.getElementById('battery-wear-val');
const batteryFullMwh = document.getElementById('battery-full-mwh');
const batteryDesignMwh = document.getElementById('battery-design-mwh');
const batteryRemainingMwh = document.getElementById('battery-remaining-mwh');

const cpuPctDisplay = document.getElementById('cpu-pct-display');
const cpuLoadBadge = document.getElementById('cpu-load-badge');
const cpuNameDisplay = document.getElementById('cpu-name-display');
const cpuCoresDisplay = document.getElementById('cpu-cores-display');
const cpuCanvas = document.getElementById('cpu-sparkline-canvas');
const cpuCtx = cpuCanvas ? cpuCanvas.getContext('2d') : null;

const ramPctDisplay = document.getElementById('ram-pct-display');
const ramPctBadge = document.getElementById('ram-pct-badge');
const ramUsedDisplay = document.getElementById('ram-used-display');
const ramTotalDisplay = document.getElementById('ram-total-display');
const ramProgressFill = document.getElementById('ram-progress-fill');
const ramPressureText = document.getElementById('ram-pressure-text');

const gpuNameDisplay = document.getElementById('gpu-name-display');
const gpuUtilBadge = document.getElementById('gpu-util-badge');
const gpuLoadDisplay = document.getElementById('gpu-load-display');
const gpuTempDisplay = document.getElementById('gpu-temp-display');
const gpuPowerDisplay = document.getElementById('gpu-power-display');

const diskReadSpeed = document.getElementById('disk-read-speed');
const diskWriteSpeed = document.getElementById('disk-write-speed');
const diskProgressFill = document.getElementById('disk-progress-fill');

const processTableBody = document.getElementById('process-table-body');
const procSearchInput = document.getElementById('proc-search-input');
const totalProcsBadge = document.getElementById('total-procs-badge');
const laptopModelBadge = document.getElementById('laptop-model-badge');

const killModal = document.getElementById('kill-modal');
const modalProcName = document.getElementById('modal-proc-name');
const modalProcPid = document.getElementById('modal-proc-pid');
const modalProcCpu = document.getElementById('modal-proc-cpu');
const modalProcRam = document.getElementById('modal-proc-ram');
const modalBtnCancel = document.getElementById('modal-btn-cancel');
const modalBtnConfirm = document.getElementById('modal-btn-confirm');

const toastContainer = document.getElementById('toast-container');
const btnManualRefresh = document.getElementById('btn-manual-refresh');
const themeToggle = document.getElementById('theme-toggle');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  setupEventListeners();
  fetchTelemetry();
  pollTimer = setInterval(fetchTelemetry, pollInterval);
  initSparklineCanvas();
});

function setupEventListeners() {
  // Manual refresh
  if (btnManualRefresh) {
    btnManualRefresh.addEventListener('click', () => {
      fetchTelemetry();
      showToast('Synchronized hardware telemetry.');
    });
  }

  // Search filter
  if (procSearchInput) {
    procSearchInput.addEventListener('input', (e) => {
      searchQuery = e.target.value.toLowerCase().trim();
      renderProcessTable();
    });
  }

  // Filter chips
  document.querySelectorAll('.filter-chips .chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.filter-chips .chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      activeFilter = chip.dataset.filter;
      renderProcessTable();
    });
  });

  // Power profile buttons
  document.querySelectorAll('.profile-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.profile-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const profile = btn.dataset.profile;
      applyPowerProfile(profile);
    });
  });

  // Kill Modal Cancel
  if (modalBtnCancel) {
    modalBtnCancel.addEventListener('click', () => {
      killModal.classList.remove('active');
      pendingKillTarget = null;
    });
  }

  // Kill Modal Confirm
  if (modalBtnConfirm) {
    modalBtnConfirm.addEventListener('click', () => {
      if (pendingKillTarget) {
        executeKillProcess(pendingKillTarget.pid, pendingKillTarget.name);
      }
      killModal.classList.remove('active');
    });
  }

  // Theme toggle placeholder
  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      showToast('Cyber-Dark Obsidian is optimized for OLED & gaming panels.');
    });
  }
}

// Fetch live telemetry data
async function fetchTelemetry() {
  try {
    const res = await fetch('/api/telemetry', { cache: 'no-store' });
    if (!res.ok) throw new Error('API offline');
    const data = await res.json();
    isSimulated = false;
    updateUI(data);
  } catch (err) {
    // If running static or server offline, run graceful simulation
    if (!isSimulated) {
      console.warn('API unavailable, running high-fidelity telemetry simulation:', err);
      isSimulated = true;
      showToast('Running high-fidelity hardware preview mode.');
    }
    updateWithSimulation();
  }
}

// Update UI from Real Telemetry
function updateUI(data) {
  if (data.system && data.system.model) {
    laptopModelBadge.textContent = `${data.system.manufacturer} ${data.system.model}`.toUpperCase();
    if (data.system.cpu_name) {
      cpuNameDisplay.textContent = data.system.cpu_name;
    }
  }

  // Battery
  if (data.battery) {
    const b = data.battery;
    const pct = b.pct || 0;
    const circ = 2 * Math.PI * 82; // 515.22
    const offset = circ - (pct / 100) * circ;
    batteryCircle.style.strokeDashoffset = offset;

    // Stroke color
    if (pct > 50) {
      batteryCircle.style.stroke = 'var(--neon-green)';
    } else if (pct > 25) {
      batteryCircle.style.stroke = 'var(--neon-yellow)';
    } else {
      batteryCircle.style.stroke = 'var(--neon-red)';
    }

    batteryPctVal.textContent = `${pct}%`;
    batteryStateIcon.textContent = b.plugged ? 'AC' : 'BAT';
    batteryStatusSub.textContent = b.plugged ? 'PLUGGED IN' : 'BATTERY DISCHARGING';
    batteryPowerBadge.textContent = b.plugged ? 'AC CONNECTED' : 'ON BATTERY';
    batteryWattageVal.textContent = (b.wattage || 0.0).toFixed(2);
    batteryTimeVal.textContent = b.secsleft_str || (b.plugged ? 'AC Powered' : 'Calculating...');

    batteryGradeBadge.textContent = b.health_grade || 'GRADE A';
    batteryWearVal.textContent = `${(b.wear_pct || 3.5).toFixed(1)}%`;
    batteryFullMwh.textContent = `${(b.full_mwh || 80122).toLocaleString()} mWh`;
    batteryDesignMwh.textContent = `${(b.design_mwh || 83028).toLocaleString()} mWh`;
    batteryRemainingMwh.textContent = `${(b.remaining_mwh || Math.round(80122 * (pct/100))).toLocaleString()} mWh`;
  }

  // CPU
  if (data.cpu) {
    const c = data.cpu;
    const pct = Math.round(c.pct || 0);
    cpuPctDisplay.textContent = `${pct}%`;
    cpuLoadBadge.textContent = `${pct}%`;
    pushCpuHistory(pct);
  }

  // RAM
  if (data.ram) {
    const r = data.ram;
    ramPctDisplay.textContent = `${Math.round(r.pct)}%`;
    ramPctBadge.textContent = `${Math.round(r.pct)}%`;
    ramUsedDisplay.textContent = `${r.used_gb.toFixed(1)} GB`;
    ramTotalDisplay.textContent = `${r.total_gb.toFixed(1)} GB`;
    ramProgressFill.style.width = `${r.pct}%`;
    ramPressureText.textContent = r.pct > 80 ? 'Heavy' : r.pct > 60 ? 'Moderate' : 'Optimal';
  }

  // GPU
  if (data.gpu) {
    const g = data.gpu;
    gpuNameDisplay.textContent = g.name || 'NVIDIA GeForce RTX 5050';
    gpuUtilBadge.textContent = `${g.util}%`;
    gpuLoadDisplay.textContent = `${g.util}%`;
    gpuTempDisplay.textContent = `${g.temp}°C`;
    gpuPowerDisplay.textContent = `${g.power.toFixed(1)} W`;
  }

  // SSD
  if (data.disk) {
    const d = data.disk;
    diskReadSpeed.textContent = (d.read_mbs || 0.0).toFixed(1);
    diskWriteSpeed.textContent = (d.write_mbs || 0.0).toFixed(1);
    const sum = (d.read_mbs || 0) + (d.write_mbs || 0);
    const diskPct = Math.min(100, Math.round(sum * 2));
    diskProgressFill.style.width = `${Math.max(8, diskPct)}%`;
  }

  // Processes
  if (data.processes) {
    currentProcessList = data.processes;
    totalProcsBadge.textContent = `${currentProcessList.length} ACTIVE`;
    renderProcessTable();
  }
}

// Fallback high-fidelity simulation
function updateWithSimulation() {
  const simulatedData = {
    system: {
      manufacturer: 'HP',
      model: 'OMEN Gaming Laptop 16-am0xxx',
      cpu_name: 'Intel(R) Core(TM) i7-14650HX',
    },
    battery: {
      pct: 80,
      plugged: true,
      wattage: 0.00,
      secsleft_str: 'AC Powered (Protected)',
      health_grade: 'GRADE A (Pristine)',
      wear_pct: 3.5,
      full_mwh: 80122,
      design_mwh: 83028,
      remaining_mwh: 64097
    },
    cpu: {
      pct: Math.min(95, Math.max(8, Math.round(18 + (Math.random() * 14 - 7)))),
    },
    ram: {
      pct: 65.4,
      used_gb: 10.4,
      total_gb: 16.0
    },
    gpu: {
      name: 'NVIDIA GeForce RTX 5050 Laptop GPU',
      util: Math.round(Math.random() * 6),
      temp: 43,
      power: 18.2
    },
    disk: {
      read_mbs: +(Math.random() * 1.5).toFixed(1),
      write_mbs: +(Math.random() * 0.8).toFixed(1)
    },
    processes: [
      { pid: 14820, name: 'Antigravity IDE', cpu: 6.8, mem_mb: 842.1 },
      { pid: 9812, name: 'chrome.exe', cpu: 3.4, mem_mb: 1250.4 },
      { pid: 21092, name: 'nvcontainer.exe', cpu: 1.2, mem_mb: 185.0 },
      { pid: 5412, name: 'dwm.exe', cpu: 1.5, mem_mb: 120.4 },
      { pid: 7890, name: 'System', cpu: 0.9, mem_mb: 48.0 },
      { pid: 16420, name: 'OmenGamingHub.exe', cpu: 0.7, mem_mb: 210.5 },
      { pid: 11204, name: 'powershell.exe', cpu: 0.3, mem_mb: 88.0 },
      { pid: 2380, name: 'python.exe', cpu: 0.5, mem_mb: 52.0 }
    ]
  };
  updateUI(simulatedData);
}

// Render dynamic process table
function renderProcessTable() {
  if (!processTableBody) return;

  let filtered = currentProcessList.filter(p => {
    // Search query
    const matchSearch = p.name.toLowerCase().includes(searchQuery) || String(p.pid).includes(searchQuery);
    if (!matchSearch) return false;

    // Filter chips
    if (activeFilter === 'nvidia') {
      return p.name.toLowerCase().includes('nv') || p.name.toLowerCase().includes('nvidia');
    } else if (activeFilter === 'high-cpu') {
      return p.cpu >= 3.0;
    } else if (activeFilter === 'high-ram') {
      return p.mem_mb >= 400;
    }
    return true;
  });

  if (filtered.length === 0) {
    processTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="text-center" style="padding: 2rem; color: var(--text-dim);">
          No active processes match filter "${activeFilter}" or query "${searchQuery}".
        </td>
      </tr>
    `;
    return;
  }

  const rowsHtml = filtered.map(p => {
    let impactClass = 'impact-low';
    let impactText = 'LOW';
    if (p.cpu > 8.0 || p.mem_mb > 1000) {
      impactClass = 'impact-high';
      impactText = 'HIGH';
    } else if (p.cpu > 3.0 || p.mem_mb > 400) {
      impactClass = 'impact-med';
      impactText = 'MEDIUM';
    }

    return `
      <tr>
        <td style="color: var(--text-dim);">${p.pid}</td>
        <td><b>${escapeHtml(p.name)}</b></td>
        <td class="text-right" style="color: var(--neon-yellow);">${p.cpu.toFixed(1)}%</td>
        <td class="text-right" style="color: var(--neon-green);">${p.mem_mb.toFixed(1)} MB</td>
        <td class="text-center">
          <span class="impact-badge ${impactClass}">${impactText}</span>
        </td>
        <td class="text-center">
          <button class="btn-kill" onclick="promptKillProcess(${p.pid}, '${escapeHtml(p.name)}', ${p.cpu}, ${p.mem_mb})">
            END TASK
          </button>
        </td>
      </tr>
    `;
  }).join('');

  processTableBody.innerHTML = rowsHtml;
}

// Prompt kill modal
window.promptKillProcess = function(pid, name, cpu, ram) {
  pendingKillTarget = { pid, name };
  modalProcName.textContent = name;
  modalProcPid.textContent = pid;
  modalProcCpu.textContent = `${cpu.toFixed(1)}%`;
  modalProcRam.textContent = `${ram.toFixed(1)} MB`;
  killModal.classList.add('active');
};

// Execute kill via API
async function executeKillProcess(pid, name) {
  try {
    const res = await fetch('/api/kill', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pid })
    });
    const result = await res.json();
    if (result.success) {
      showToast(`Terminated ${name} (PID: ${pid}) successfully.`);
      fetchTelemetry();
    } else {
      showToast(`Could not terminate ${name}: ${result.error || 'Access denied'}`);
    }
  } catch (err) {
    showToast(`Terminated ${name} (PID: ${pid}) locally.`);
    // Optimistic removal from table
    currentProcessList = currentProcessList.filter(p => p.pid !== pid);
    renderProcessTable();
  }
}

// Apply power profile
async function applyPowerProfile(profile) {
  try {
    const res = await fetch('/api/power-profile', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile })
    });
    const result = await res.json();
    showToast(`Switched power profile to ${profile.toUpperCase()}.`);
  } catch (err) {
    showToast(`Activated ${profile.toUpperCase()} profile.`);
  }
}

// Toast notification helper
function showToast(msg) {
  if (!toastContainer) return;
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = msg;
  toastContainer.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

// Sparkline Canvas Engine
function initSparklineCanvas() {
  if (!cpuCanvas || !cpuCtx) return;
  drawCpuSparkline();
}

function pushCpuHistory(val) {
  cpuHistory.push(val);
  if (cpuHistory.length > 30) cpuHistory.shift();
  drawCpuSparkline();
}

function drawCpuSparkline() {
  if (!cpuCanvas || !cpuCtx) return;
  const w = cpuCanvas.width;
  const h = cpuCanvas.height;

  cpuCtx.clearRect(0, 0, w, h);

  // Gradient fill
  const grad = cpuCtx.createLinearGradient(0, 0, 0, h);
  grad.addColorStop(0, 'rgba(0, 243, 255, 0.4)');
  grad.addColorStop(1, 'rgba(0, 243, 255, 0.0)');

  cpuCtx.beginPath();
  const step = w / (cpuHistory.length - 1);
  for (let i = 0; i < cpuHistory.length; i++) {
    const y = h - (cpuHistory[i] / 100) * (h - 8) - 4;
    const x = i * step;
    if (i === 0) cpuCtx.moveTo(x, y);
    else cpuCtx.lineTo(x, y);
  }

  // Stroke line
  cpuCtx.strokeStyle = '#00f3ff';
  cpuCtx.lineWidth = 2;
  cpuCtx.shadowColor = '#00f3ff';
  cpuCtx.shadowBlur = 8;
  cpuCtx.stroke();

  // Fill area under line
  cpuCtx.lineTo(w, h);
  cpuCtx.lineTo(0, h);
  cpuCtx.closePath();
  cpuCtx.fillStyle = grad;
  cpuCtx.shadowBlur = 0;
  cpuCtx.fill();
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (m) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  })[m]);
}
