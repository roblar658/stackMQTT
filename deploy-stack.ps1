# ==============================================================================
# deploy-stack.ps1 - Complete Smart House Stack with Real Equipment Images
# EMQX Broker | Home Assistant | Zigbee2MQTT | Zabbix 7.0 | 3D Digital Twin
# ==============================================================================
$ErrorActionPreference = "Stop"
$ProjectDir = "$PSScriptRoot\smarthouse-stack"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Trygt generert gradtegn som aldri blir korrupt til Â°C uavhengig av editor/tegnsett
$degC = "$([char]176)C"

function Get-AvailablePort([int]$startPort) {
    $port = $startPort
    while ($true) {
        $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if (-not $conn) {
            return $port
        }
        $port++
    }
}

# ------------------------------------------------------------------------------
# 0. Check & Start Docker Desktop
# ------------------------------------------------------------------------------
Write-Host "==> Verifying Docker Desktop status..." -ForegroundColor Cyan

& docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker daemon is not running. Launching Docker Desktop..." -ForegroundColor Yellow
    $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerPath) {
        Start-Process $dockerPath
    } else {
        Write-Error "Docker Desktop executable not found at: $dockerPath. Please launch it manually."
        exit 1
    }

    Write-Host "Waiting for Docker daemon to initialize..." -ForegroundColor Yellow
    $timeout = 90
    $elapsed = 0
    $dockerReady = $false

    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        & docker info > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            $dockerReady = $true
            break
        }
        Write-Host "  ... waiting ($elapsed / $timeout seconds)" -ForegroundColor Gray
    }

    if (-not $dockerReady) {
        Write-Error "Timeout: Docker daemon did not respond within $timeout seconds."
        exit 1
    }
}
Write-Host "Docker daemon is active and ready." -ForegroundColor Green

# ------------------------------------------------------------------------------
# 1. Cleanup Old Containers & Allocate Free Ports
# ------------------------------------------------------------------------------
Write-Host "==> Cleaning up older containers..." -ForegroundColor Cyan
& docker rm -f smarthouse-bridge smarthouse-broker smarthouse-app smarthouse-homeassistant zabbix-server zabbix-web zabbix-agent2 zabbix-db > $null 2>&1

$z2mPort  = Get-AvailablePort 8085
$zbxPort  = Get-AvailablePort 8080
$emqxPort = Get-AvailablePort 18083
$haPort   = Get-AvailablePort 8123

Write-Host "Port Allocations:" -ForegroundColor Green
Write-Host "  * EMQX Broker Dashboard   : $emqxPort"
Write-Host "  * Home Assistant Portal   : $haPort"
Write-Host "  * Zigbee2MQTT Frontend    : $z2mPort"
Write-Host "  * Zabbix Web Portal       : $zbxPort"
Write-Host "  * 3D Digital Twin / Web   : 3000"

# ------------------------------------------------------------------------------
# 2. Directory Structure
# ------------------------------------------------------------------------------
Write-Host "==> Ensuring project folder structure exists..." -ForegroundColor Cyan
$dirsToCreate = @(
    "$ProjectDir\zigbee2mqtt\data",
    "$ProjectDir\homeassistant\config",
    "$ProjectDir\homeassistant\config\themes",
    "$ProjectDir\app\src",
    "$ProjectDir\app\public"
)
foreach ($dir in $dirsToCreate) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

# ------------------------------------------------------------------------------
# 3. Zigbee2MQTT Configuration
# ------------------------------------------------------------------------------
$z2mConfig = @"
homeassistant:
  enabled: true
permit_join: true
mqtt:
  base_topic: zigbee2mqtt
  server: 'mqtt://emqx:1883'
serial:
  port: null
frontend:
  port: 8080
  host: 0.0.0.0
advanced:
  log_level: info
"@
[System.IO.File]::WriteAllText("$ProjectDir\zigbee2mqtt\data\configuration.yaml", $z2mConfig, $Utf8NoBom)

# ------------------------------------------------------------------------------
# 4. Home Assistant Configuration
# ------------------------------------------------------------------------------
$haConfig = @"
default_config:

frontend:
  themes: !include_dir_merge_named themes

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 10.0.0.0/8

mqtt:
  sensor:
    - name: "Living Room Temperature"
      unique_id: "living_room_temperature"
      state_topic: "zigbee2mqtt/living_room/temperature"
      value_template: "{{ value_json.value }}"
      unit_of_measurement: "$degC"
      device_class: "temperature"
    - name: "Living Room Humidity"
      unique_id: "living_room_humidity"
      state_topic: "zigbee2mqtt/living_room/humidity"
      value_template: "{{ value_json.value }}"
      unit_of_measurement: "%"
      device_class: "humidity"
    - name: "Living Room CO2"
      unique_id: "living_room_co2"
      state_topic: "zigbee2mqtt/living_room/co2"
      value_template: "{{ value_json.value }}"
      unit_of_measurement: "ppm"
      device_class: "carbon_dioxide"
    - name: "Kitchen Temperature"
      unique_id: "kitchen_temperature"
      state_topic: "zigbee2mqtt/kitchen/temperature"
      value_template: "{{ value_json.value }}"
      unit_of_measurement: "$degC"
      device_class: "temperature"
    - name: "Bedroom Temperature"
      unique_id: "bedroom_temperature"
      state_topic: "zigbee2mqtt/bedroom/temperature"
      value_template: "{{ value_json.value }}"
      unit_of_measurement: "$degC"
      device_class: "temperature"
    - name: "Office Temperature"
      unique_id: "office_temperature"
      state_topic: "zigbee2mqtt/office/temperature"
      value_template: "{{ value_json.value }}"
      unit_of_measurement: "$degC"
      device_class: "temperature"
  binary_sensor:
    - name: "Living Room Motion"
      unique_id: "living_room_motion"
      state_topic: "zigbee2mqtt/living_room/motion"
      value_template: "{{ 'ON' if value_json.value == 1 else 'OFF' }}"
      device_class: "motion"
    - name: "Kitchen Smoke"
      unique_id: "kitchen_smoke"
      state_topic: "zigbee2mqtt/kitchen/smoke"
      value_template: "{{ 'ON' if value_json.value == 1 else 'OFF' }}"
      device_class: "smoke"
    - name: "Bedroom Motion"
      unique_id: "bedroom_motion"
      state_topic: "zigbee2mqtt/bedroom/motion"
      value_template: "{{ 'ON' if value_json.value == 1 else 'OFF' }}"
      device_class: "motion"
    - name: "Office Motion"
      unique_id: "office_motion"
      state_topic: "zigbee2mqtt/office/motion"
      value_template: "{{ 'ON' if value_json.value == 1 else 'OFF' }}"
      device_class: "motion"

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
"@
[System.IO.File]::WriteAllText("$ProjectDir\homeassistant\config\configuration.yaml", $haConfig, $Utf8NoBom)

if (-not (Test-Path "$ProjectDir\homeassistant\config\automations.yaml")) {
    New-Item -ItemType File -Force -Path "$ProjectDir\homeassistant\config\automations.yaml" | Out-Null
}
if (-not (Test-Path "$ProjectDir\homeassistant\config\scripts.yaml")) {
    New-Item -ItemType File -Force -Path "$ProjectDir\homeassistant\config\scripts.yaml" | Out-Null
}
if (-not (Test-Path "$ProjectDir\homeassistant\config\scenes.yaml")) {
    New-Item -ItemType File -Force -Path "$ProjectDir\homeassistant\config\scenes.yaml" | Out-Null
}

# Auto-configure MQTT Integration with EMQX (only if not configured already)
if (-not (Test-Path "$ProjectDir\homeassistant\config\.storage\core.config_entries")) {
    New-Item -ItemType Directory -Force -Path "$ProjectDir\homeassistant\config\.storage" | Out-Null
    $haConfigEntries = @'
{
  "version": 1,
  "minor_version": 1,
  "key": "core.config_entries",
  "data": {
    "entries": [
      {
        "entry_id": "01J8MQTTBROKERCONFIGENTRY001",
        "version": 1,
        "minor_version": 1,
        "domain": "mqtt",
        "title": "emqx",
        "data": {
          "broker": "emqx",
          "port": 1883,
          "discovery": true,
          "discovery_prefix": "homeassistant"
        },
        "options": {},
        "pref_disable_new_entities": false,
        "pref_disable_polling": false,
        "source": "user",
        "unique_id": null,
        "disabled_by": null
      }
    ]
  }
}
'@
    [System.IO.File]::WriteAllText("$ProjectDir\homeassistant\config\.storage\core.config_entries", $haConfigEntries, $Utf8NoBom)
}

# ------------------------------------------------------------------------------
# 5. Application Package & TypeScript Definitions
# ------------------------------------------------------------------------------
$packageJson = @'
{
  "name": "smarthouse-ts-stack",
  "version": "1.0.0",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "mqtt": "^5.5.0",
    "rxjs": "^7.8.1",
    "ws": "^8.16.0",
    "zod": "^3.22.4"
  },
  "devDependencies": {
    "@types/node": "^20.11.0",
    "@types/ws": "^8.5.10",
    "typescript": "^5.4.0"
  }
}
'@
[System.IO.File]::WriteAllText("$ProjectDir\app\package.json", $packageJson, $Utf8NoBom)

$tsconfigJson = @'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM"],
    "module": "CommonJS",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
'@
[System.IO.File]::WriteAllText("$ProjectDir\app\tsconfig.json", $tsconfigJson, $Utf8NoBom)

# ------------------------------------------------------------------------------
# 6. Backend App: Telemetry, Persistent Events & Zabbix 7.0 Complete Auto-Setup
# ------------------------------------------------------------------------------
$appIndexTs = @'
import { EventEmitter } from "events";
import * as mqtt from "mqtt";
import { Subject } from "rxjs";
import { WebSocketServer, WebSocket } from "ws";
import { z } from "zod";
import * as http from "http";
import * as fs from "fs";
import * as path from "path";

const ROOMS = ["living_room", "kitchen", "bedroom", "office"] as const;
type Room = typeof ROOMS[number];

const SensorTelemetrySchema = z.object({
  room: z.enum(ROOMS),
  sensorType: z.enum(["temperature", "humidity", "co2", "motion", "smoke"]),
  value: z.number(),
  timestamp: z.number().default(() => Date.now()),
});

interface RoomState {
  temperature: number;
  humidity: number;
  co2: number;
  motion: number;
  smoke: number;
  lastTempTimestamp: number;
  prevTemperature: number;
}

const houseState: Record<Room, RoomState> = {
  living_room: { temperature: 21.5, humidity: 45, co2: 600, motion: 0, smoke: 0, lastTempTimestamp: Date.now(), prevTemperature: 21.5 },
  kitchen:     { temperature: 22.0, humidity: 50, co2: 650, motion: 0, smoke: 0, lastTempTimestamp: Date.now(), prevTemperature: 22.0 },
  bedroom:     { temperature: 19.5, humidity: 42, co2: 550, motion: 0, smoke: 0, lastTempTimestamp: Date.now(), prevTemperature: 19.5 },
  office:      { temperature: 21.0, humidity: 44, co2: 700, motion: 0, smoke: 0, lastTempTimestamp: Date.now(), prevTemperature: 21.0 },
};

const sensorStatus: Record<string, boolean> = {
  "living_room_pir": true,
  "living_room_climate": true,
  "kitchen_smoke": true,
  "kitchen_climate": true,
  "bedroom_pir": true,
  "bedroom_climate": true,
  "office_pir": true,
  "office_climate": true,
};

let simulatedFireActive = false;
let simulatedCo2SpikeActive = false;

const subsystems = {
  alarmArmed: true,
  fireAlarm: { active: 0, room: "none", reason: "none" },
  burglarAlarm: { active: 0, detectedRooms: [] as string[] },
  ventilation: { level: 1, targetRpm: 1200, maxCo2: 700, avgHumidity: 45.2 },
  hvac: { heatingActive: false, coolingActive: false, targetTemp: 21.0 },
};

class IngestionBus extends EventEmitter {}
const bus = new IngestionBus();

const mqttClient = mqtt.connect("mqtt://emqx:1883", {
  clientId: "smart-house-controller",
  clean: true,
});

function evaluateSubsystems() {
  let fireDetected = false;
  let fireRoom = "none";
  let fireReason = "none";
  const motionRooms: string[] = [];
  let maxCo2 = 0;
  let totalHumidity = 0;
  let totalTemp = 0;

  for (const r of ROOMS) {
    const state = houseState[r];
    totalHumidity += state.humidity;
    totalTemp += state.temperature;
    if (state.co2 > maxCo2) maxCo2 = state.co2;
    if (state.motion === 1) motionRooms.push(r);

    const tempRate = state.temperature - state.prevTemperature;
    if (state.smoke === 1 && (tempRate > 2.0 || state.temperature > 32)) {
      fireDetected = true;
      fireRoom = r;
      fireReason = `Smoke detected with rapid heat increase (+${tempRate.toFixed(1)}\u00B0C)`;
    } else if (state.temperature > 55) {
      fireDetected = true;
      fireRoom = r;
      fireReason = `Extreme heat threshold breached (${state.temperature}\u00B0C)`;
    } else if (state.smoke === 1) {
      fireDetected = true;
      fireRoom = r;
      fireReason = "Smoke detector triggered";
    }
  }

  subsystems.fireAlarm = { active: fireDetected ? 1 : 0, room: fireRoom, reason: fireReason };
  subsystems.burglarAlarm = {
    active: subsystems.alarmArmed && motionRooms.length > 0 ? 1 : 0,
    detectedRooms: motionRooms,
  };

  const avgHumidity = parseFloat((totalHumidity / ROOMS.length).toFixed(1));
  let ventLevel = 1;
  if (maxCo2 > 1200 || avgHumidity > 65) ventLevel = 3;
  else if (maxCo2 > 800 || avgHumidity > 55) ventLevel = 2;

  subsystems.ventilation = { level: ventLevel, targetRpm: ventLevel * 700, maxCo2, avgHumidity };

  const avgTemp = totalTemp / ROOMS.length;
  subsystems.hvac = {
    targetTemp: 21.0,
    heatingActive: avgTemp < 20.0,
    coolingActive: avgTemp > 22.5,
  };
}

mqttClient.on("connect", () => {
  console.log("[Broker Layer] Connected to EMQX Broker on port 1883.");
  mqttClient.subscribe("zigbee2mqtt/+/+");

  setInterval(() => {
    for (const r of ROOMS) {
      if (sensorStatus[`${r}_climate`]) {
        let curT = houseState[r].temperature;
        if (!simulatedFireActive || r !== "kitchen") {
          curT = parseFloat((curT + (Math.random() * 0.3 - 0.15)).toFixed(2));
          houseState[r].temperature = curT;
        }
        mqttClient.publish(`zigbee2mqtt/${r}/temperature`, JSON.stringify({ room: r, sensorType: "temperature", value: curT }));

        const h = parseFloat((45 + (Math.random() * 6 - 3)).toFixed(1));
        houseState[r].humidity = h;
        mqttClient.publish(`zigbee2mqtt/${r}/humidity`, JSON.stringify({ room: r, sensorType: "humidity", value: h }));

        let co2 = Math.round(550 + Math.random() * 200);
        if (r === "living_room" && simulatedCo2SpikeActive) {
          co2 = 1450;
        }
        houseState[r].co2 = co2;
        mqttClient.publish(`zigbee2mqtt/${r}/co2`, JSON.stringify({ room: r, sensorType: "co2", value: co2 }));
      }

      if (sensorStatus[`${r}_pir`]) {
        const motion = Math.random() > 0.90 ? 1 : 0;
        houseState[r].motion = motion;
        mqttClient.publish(`zigbee2mqtt/${r}/motion`, JSON.stringify({ room: r, sensorType: "motion", value: motion }));
      } else {
        houseState[r].motion = 0;
      }

      if (r === "kitchen") {
        if (!sensorStatus["kitchen_smoke"]) {
          houseState.kitchen.smoke = 0;
        } else if (simulatedFireActive) {
          houseState.kitchen.smoke = 1;
        }
        mqttClient.publish("zigbee2mqtt/kitchen/smoke", JSON.stringify({ room: "kitchen", sensorType: "smoke", value: houseState.kitchen.smoke }));
      }
    }

    evaluateSubsystems();
    broadcastState();
  }, 2500);
});

mqttClient.on("message", (topic, payload) => {
  try {
    const raw = JSON.parse(payload.toString());
    bus.emit("raw_telemetry", raw);
  } catch {}
});

const telemetrySubject$ = new Subject<unknown>();
bus.on("raw_telemetry", (data) => telemetrySubject$.next(data));

telemetrySubject$.subscribe((data) => {
  const result = SensorTelemetrySchema.safeParse(data);
  if (!result.success) return;

  const { room, sensorType, value } = result.data;
  const currentRoom = houseState[room];

  if (sensorType === "temperature") {
    currentRoom.prevTemperature = currentRoom.temperature;
    currentRoom.temperature = value;
    currentRoom.lastTempTimestamp = Date.now();
  } else if (sensorType === "humidity") {
    currentRoom.humidity = value;
  } else if (sensorType === "co2") {
    currentRoom.co2 = value;
  } else if (sensorType === "motion") {
    if (sensorStatus[`${room}_pir`]) currentRoom.motion = value;
  } else if (sensorType === "smoke") {
    if (sensorStatus[`${room}_smoke`]) currentRoom.smoke = value;
  }

  evaluateSubsystems();
  broadcastState();
});

const server = http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url || "", `http://${req.headers.host}`);

  if (url.pathname === "/api/toggle-sensor") {
    const id = url.searchParams.get("id");
    if (id && id in sensorStatus) {
      sensorStatus[id] = !sensorStatus[id];
      evaluateSubsystems();
      broadcastState();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ id, enabled: sensorStatus[id] }));
      return;
    }
    res.writeHead(400, { "Content-Type": "text/plain" });
    res.end("Invalid sensor id");
    return;
  }

  if (url.pathname === "/api/event") {
    const type = url.searchParams.get("type");
    if (type === "fire") {
      simulatedFireActive = true;
      houseState.kitchen.smoke = 1;
      houseState.kitchen.prevTemperature = houseState.kitchen.temperature;
      houseState.kitchen.temperature = 65.0;
      mqttClient.publish("zigbee2mqtt/kitchen/smoke", JSON.stringify({ room: "kitchen", sensorType: "smoke", value: 1 }));
      mqttClient.publish("zigbee2mqtt/kitchen/temperature", JSON.stringify({ room: "kitchen", sensorType: "temperature", value: 65.0 }));
    } else if (type === "clear_fire") {
      simulatedFireActive = false;
      houseState.kitchen.smoke = 0;
      houseState.kitchen.prevTemperature = 22.0;
      houseState.kitchen.temperature = 22.0;
      mqttClient.publish("zigbee2mqtt/kitchen/smoke", JSON.stringify({ room: "kitchen", sensorType: "smoke", value: 0 }));
      mqttClient.publish("zigbee2mqtt/kitchen/temperature", JSON.stringify({ room: "kitchen", sensorType: "temperature", value: 22.0 }));
    } else if (type === "co2_spike") {
      simulatedCo2SpikeActive = !simulatedCo2SpikeActive;
      const co2Val = simulatedCo2SpikeActive ? 1450 : 600;
      houseState.living_room.co2 = co2Val;
      mqttClient.publish("zigbee2mqtt/living_room/co2", JSON.stringify({ room: "living_room", sensorType: "co2", value: co2Val }));
    } else if (type === "freeze") {
      ROOMS.forEach((r) => {
        houseState[r].prevTemperature = houseState[r].temperature;
        houseState[r].temperature = 16.0;
        mqttClient.publish(`zigbee2mqtt/${r}/temperature`, JSON.stringify({ room: r, sensorType: "temperature", value: 16.0 }));
      });
    } else if (type === "heatwave") {
      ROOMS.forEach((r) => {
        houseState[r].prevTemperature = houseState[r].temperature;
        houseState[r].temperature = 28.5;
        mqttClient.publish(`zigbee2mqtt/${r}/temperature`, JSON.stringify({ room: r, sensorType: "temperature", value: 28.5 }));
      });
    } else if (type === "toggle_arm") {
      subsystems.alarmArmed = !subsystems.alarmArmed;
    }

    evaluateSubsystems();
    broadcastState();
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", event: type }));
    return;
  }

  if (url.pathname === "/api/metrics") {
    const flatMetrics: Record<string, number> = {
      living_room_temp: houseState.living_room.temperature,
      living_room_humidity: houseState.living_room.humidity,
      living_room_co2: houseState.living_room.co2,
      living_room_motion: houseState.living_room.motion,
      living_room_smoke: houseState.living_room.smoke,

      kitchen_temp: houseState.kitchen.temperature,
      kitchen_humidity: houseState.kitchen.humidity,
      kitchen_co2: houseState.kitchen.co2,
      kitchen_motion: houseState.kitchen.motion,
      kitchen_smoke: houseState.kitchen.smoke,

      bedroom_temp: houseState.bedroom.temperature,
      bedroom_humidity: houseState.bedroom.humidity,
      bedroom_co2: houseState.bedroom.co2,
      bedroom_motion: houseState.bedroom.motion,
      bedroom_smoke: houseState.bedroom.smoke,

      office_temp: houseState.office.temperature,
      office_humidity: houseState.office.humidity,
      office_co2: houseState.office.co2,
      office_motion: houseState.office.motion,
      office_smoke: houseState.office.smoke,

      fire_alarm_active: subsystems.fireAlarm.active,
      burglar_alarm_active: subsystems.burglarAlarm.active,
      ventilation_level: subsystems.ventilation.level,
      ventilation_max_co2: subsystems.ventilation.maxCo2,
      hvac_heating_active: subsystems.hvac.heatingActive ? 1 : 0,
      hvac_cooling_active: subsystems.hvac.coolingActive ? 1 : 0
    };
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(flatMetrics));
    return;
  }

  const filePath = path.join(__dirname, "../public/index.html");
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(500);
      res.end("Failed to load 3D Digital Twin UI");
      return;
    }
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server });
function broadcastState() {
  const payload = JSON.stringify({
    houseState,
    subsystems,
    sensorStatus,
    activeEvents: {
      fire: simulatedFireActive,
      co2_spike: simulatedCo2SpikeActive,
      alarmArmed: subsystems.alarmArmed,
      heating: subsystems.hvac.heatingActive,
      cooling: subsystems.hvac.coolingActive
    },
    timestamp: Date.now()
  });
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) client.send(payload);
  });
}

server.listen(3000, () => {
  console.log("[Application Layer] Web, WebSocket, and Zabbix Metrics running on port 3000");
});

async function zabbixApiCall(method: string, params: any, auth: string | null = null) {
  const body: any = { jsonrpc: "2.0", method, params, id: Date.now() };
  const headers: Record<string, string> = { "Content-Type": "application/json-rpc" };
  if (auth) {
    headers["Authorization"] = `Bearer ${auth}`;
  }
  const res = await fetch("http://zabbix-web:8080/api_jsonrpc.php", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  return await res.json();
}

async function initZabbixProvisioning() {
  console.log("[Zabbix Setup] Connecting to Zabbix API...");
  let loggedIn = false;
  let authToken = "";
  while (!loggedIn) {
    try {
      const loginRes: any = await zabbixApiCall("user.login", { username: "Admin", password: "zabbix" });
      if (loginRes?.result) {
        authToken = loginRes.result;
        loggedIn = true;
        console.log("[Zabbix Setup] Authenticated to Zabbix via Bearer Token.");
      }
    } catch {}
    if (!loggedIn) await new Promise((r) => setTimeout(r, 5000));
  }

  try {
    let groupRes: any = await zabbixApiCall("hostgroup.get", { filter: { name: ["Smart House"] } }, authToken);
    let groupId = groupRes.result?.[0]?.groupid;
    if (!groupId) {
      const created = await zabbixApiCall("hostgroup.create", { name: "Smart House" }, authToken);
      groupId = created.result.groupids[0];
    }

    let hostRes: any = await zabbixApiCall("host.get", { filter: { host: ["Smart-House-System"] } }, authToken);
    let hostId = hostRes.result?.[0]?.hostid;
    if (!hostId) {
      const hostCreated = await zabbixApiCall("host.create", {
        host: "Smart-House-System",
        interfaces: [{ type: 1, main: 1, useip: 0, dns: "app", ip: "", port: "3000" }],
        groups: [{ groupid: groupId }],
      }, authToken);
      hostId = hostCreated.result.hostids[0];
    }

    let agentHostRes: any = await zabbixApiCall("host.get", { filter: { host: ["Docker-Desktop-Host"] } }, authToken);
    let agentHostId = agentHostRes.result?.[0]?.hostid;
    if (!agentHostId) {
      await zabbixApiCall("host.create", {
        host: "Docker-Desktop-Host",
        interfaces: [{ type: 1, main: 1, useip: 0, dns: "zabbix-agent2", ip: "", port: "10050" }],
        groups: [{ groupid: groupId }],
      }, authToken);
      console.log("[Zabbix Setup] Provisioned Docker-Desktop-Host for active agent checks.");
    }

    let masterItemRes: any = await zabbixApiCall("item.get", { hostids: hostId, filter: { key_: ["smarthouse.metrics"] } }, authToken);
    let masterItemId = masterItemRes.result?.[0]?.itemid;
    if (!masterItemId) {
      const mItem = await zabbixApiCall("item.create", {
        name: "Smart House Telemetry Master Poll",
        key_: "smarthouse.metrics",
        hostid: hostId,
        type: 19,
        url: "http://app:3000/api/metrics",
        value_type: 4,
        delay: "3s",
      }, authToken);
      masterItemId = mItem.result.itemids[0];
    }

    const metricsToCreate = [
      ...ROOMS.flatMap((r) => [
        { key: `${r}_temp`, name: `${r.replace("_"," ").toUpperCase()} Temperature`, type: 0, unit: "\u00B0C" },
        { key: `${r}_humidity`, name: `${r.replace("_"," ").toUpperCase()} Humidity`, type: 0, unit: "%" },
        { key: `${r}_co2`, name: `${r.replace("_"," ").toUpperCase()} CO2`, type: 3, unit: "ppm" },
        { key: `${r}_motion`, name: `${r.replace("_"," ").toUpperCase()} Motion`, type: 3, unit: "" },
        { key: `${r}_smoke`, name: `${r.replace("_"," ").toUpperCase()} Smoke`, type: 3, unit: "" },
      ]),
      { key: "fire_alarm_active", name: "Fire Alarm Status", type: 3, unit: "" },
      { key: "burglar_alarm_active", name: "Burglar Alarm Status", type: 3, unit: "" },
      { key: "ventilation_level", name: "Ventilation Stage", type: 3, unit: "Stage" },
      { key: "ventilation_max_co2", name: "Max CO2 Reading", type: 3, unit: "ppm" },
      { key: "hvac_heating_active", name: "Heating System Active", type: 3, unit: "" },
      { key: "hvac_cooling_active", name: "Cooling System Active", type: 3, unit: "" },
    ];

    for (const m of metricsToCreate) {
      const existing: any = await zabbixApiCall("item.get", { hostids: hostId, filter: { key_: [m.key] } }, authToken);
      if (existing.result.length === 0) {
        await zabbixApiCall("item.create", {
          name: m.name,
          key_: m.key,
          hostid: hostId,
          type: 18,
          master_itemid: masterItemId,
          value_type: m.type,
          units: m.unit,
          preprocessing: [{ type: "12", params: `$.${m.key}`, error_handler: "1", error_handler_params: "" }],
        }, authToken);
      }
    }

    const triggers = [
      { description: "[CRITICAL FIRE] Fire alarm triggered in house zone", expression: 'last(/Smart-House-System/fire_alarm_active)=1', priority: 5 },
      { description: "[SECURITY] Burglar alarm active in armed mode", expression: 'last(/Smart-House-System/burglar_alarm_active)=1', priority: 4 },
      { description: "[AIR QUALITY] Dangerous CO2 concentration detected (>1000 ppm)", expression: 'last(/Smart-House-System/ventilation_max_co2)>1000', priority: 3 },
      { description: "[CLIMATE] Low temperature warning (<18\u00B0C)", expression: 'last(/Smart-House-System/living_room_temp)<18', priority: 2 },
      { description: "[CLIMATE] High temperature warning (>27\u00B0C)", expression: 'last(/Smart-House-System/kitchen_temp)>27', priority: 2 },
      { description: "[HVAC] Heating system currently active", expression: 'last(/Smart-House-System/hvac_heating_active)=1', priority: 1 },
    ];

    for (const t of triggers) {
      const existTrig: any = await zabbixApiCall("trigger.get", { filter: { description: [t.description] } }, authToken);
      if (existTrig.result.length === 0) {
        await zabbixApiCall("trigger.create", { description: t.description, expression: t.expression, priority: t.priority }, authToken);
      }
    }
    console.log("[Zabbix Setup] Host, items, agent host, and all active triggers successfully provisioned.");
  } catch (e) {
    console.error("[Zabbix Provisioning Error]:", e);
  }
}
setTimeout(initZabbixProvisioning, 6000);
'@
[System.IO.File]::WriteAllText("$ProjectDir\app\src\index.ts", $appIndexTs, $Utf8NoBom)

# ------------------------------------------------------------------------------
# 7. 3D Digital Twin UI
# ------------------------------------------------------------------------------
$appIndexHtml = @'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Smart House 3D Digital Twin - Environmental & Physics Engine</title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; overflow: hidden; background: #0f172a; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; user-select: none; }
    
    #vignette-overlay {
      position: absolute; inset: 0; pointer-events: none; z-index: 5;
      transition: box-shadow 0.8s ease, background 0.8s ease;
    }
    .cold-vignette {
      box-shadow: inset 0 0 100px 30px rgba(56, 189, 248, 0.45), inset 0 0 200px rgba(186, 230, 253, 0.2);
    }
    .heat-vignette {
      box-shadow: inset 0 0 120px 40px rgba(239, 68, 68, 0.45), inset 0 0 220px rgba(249, 115, 22, 0.25);
    }
    .co2-vignette {
      box-shadow: inset 0 0 110px 35px rgba(234, 179, 8, 0.4), inset 0 0 210px rgba(163, 230, 53, 0.25);
    }

    #hud {
      position: absolute; top: 16px; left: 16px; width: 330px;
      background: rgba(15, 23, 42, 0.92); border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 12px; padding: 16px; color: #fff; box-shadow: 0 10px 30px rgba(0,0,0,0.7);
      backdrop-filter: blur(8px); z-index: 10;
    }
    #event-panel {
      position: absolute; top: 16px; right: 16px; width: 320px;
      background: rgba(15, 23, 42, 0.94); border: 1px solid rgba(255, 255, 255, 0.16);
      border-radius: 12px; padding: 14px; color: #fff; box-shadow: 0 10px 30px rgba(0,0,0,0.7);
      backdrop-filter: blur(8px); z-index: 10;
    }
    h2, h3 { margin: 0 0 8px 0; font-size: 1.05rem; color: #38bdf8; display: flex; justify-content: space-between; align-items: center; }
    h3 { font-size: 0.92rem; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 6px; }
    .room-badge { background: #1e293b; color: #38bdf8; padding: 4px 10px; border-radius: 6px; font-size: 0.82rem; font-weight: bold; border: 1px solid #334155; }
    
    .status-row { display: flex; gap: 6px; margin: 10px 0; flex-wrap: wrap; }
    .badge { padding: 4px 8px; border-radius: 6px; font-weight: bold; font-size: 0.72rem; text-transform: uppercase; }
    .badge-ok { background: #065f46; color: #6ee7b7; }
    .badge-warn { background: #92400e; color: #fde68a; }
    .badge-danger { background: #991b1b; color: #fca5a5; animation: blink 1s infinite alternate; }
    @keyframes blink { from { opacity: 0.7; } to { opacity: 1; } }
    
    .sensor-grid { background: rgba(255,255,255,0.03); border-radius: 8px; padding: 10px; margin-top: 8px; border: 1px solid rgba(255,255,255,0.06); }
    .sensor-item { display: flex; justify-content: space-between; font-size: 0.82rem; margin: 4px 0; }
    .val { font-weight: bold; color: #38bdf8; }

    #debuff-card {
      margin-top: 8px; padding: 8px 12px; border-radius: 8px; background: rgba(0,0,0,0.4);
      display: flex; align-items: center; justify-content: space-between; font-size: 0.8rem; font-weight: bold;
    }
    .state-normal { border-left: 4px solid #22c55e; color: #4ade80; }
    .state-cold { border-left: 4px solid #38bdf8; color: #7dd3fc; animation: shiver-text 0.2s infinite; }
    .state-hot { border-left: 4px solid #ef4444; color: #f87171; }
    .state-co2 { border-left: 4px solid #eab308; color: #fde047; animation: cough-text 0.4s infinite; }
    @keyframes shiver-text { 0% { transform: translateX(0); } 50% { transform: translateX(1px); } 100% { transform: translateX(-1px); } }
    @keyframes cough-text { 0% { transform: translateY(0); } 50% { transform: translateY(2px); } 100% { transform: translateY(0); } }

    #interact-prompt {
      display: none; position: absolute; top: 45%; left: 50%; transform: translate(-50%, -50%);
      background: rgba(15, 23, 42, 0.95); border: 2px solid #38bdf8; color: #fff;
      padding: 12px 24px; border-radius: 30px; font-size: 0.95rem; font-weight: bold;
      box-shadow: 0 0 25px rgba(56, 189, 248, 0.5); z-index: 30; pointer-events: none;
      text-align: center;
    }
    #interact-prompt span.key { background: #38bdf8; color: #0f172a; padding: 3px 8px; border-radius: 6px; margin-right: 6px; }

    #unstuck-toast {
      display: none; position: absolute; top: 22%; left: 50%; transform: translate(-50%, -50%);
      background: rgba(34, 197, 94, 0.95); color: #0f172a; padding: 8px 20px;
      border-radius: 20px; font-weight: bold; font-size: 0.85rem; z-index: 40;
      box-shadow: 0 0 20px rgba(34, 197, 94, 0.6); pointer-events: none;
    }

    #action-status {
      display: none; font-size: 0.76rem; font-weight: bold; padding: 6px 10px;
      margin-bottom: 8px; border-radius: 6px; background: rgba(56, 189, 248, 0.15);
      border: 1px solid #38bdf8; color: #38bdf8; text-align: center;
      transition: opacity 1s ease-out; opacity: 1;
    }

    .btn-grid { display: flex; flex-direction: column; gap: 6px; }
    .btn-evt {
      display: flex; justify-content: space-between; align-items: center;
      padding: 8px 12px; border: 1px solid rgba(255,255,255,0.12); border-radius: 6px;
      background: #1e293b; color: #cbd5e1; font-size: 0.78rem; font-weight: 600;
      cursor: pointer; text-align: left; transition: all 0.25s ease;
    }
    .btn-evt:hover { background: #334155; border-color: #38bdf8; color: #fff; }
    .tag-icon { font-size: 0.7rem; font-weight: bold; padding: 2px 6px; border-radius: 4px; background: rgba(255,255,255,0.08); margin-right: 8px; }

    .btn-evt.btn-persistent-active {
      background: #0284c7 !important; border-color: #38bdf8 !important; color: #ffffff !important;
      box-shadow: 0 0 12px rgba(56, 189, 248, 0.45);
    }
    .btn-evt.btn-persistent-co2 {
      background: #a16207 !important; border-color: #eab308 !important; color: #ffffff !important;
      box-shadow: 0 0 14px rgba(234, 179, 8, 0.5);
    }
    .btn-evt.btn-persistent-fire {
      background: #b91c1c !important; border-color: #ef4444 !important; color: #ffffff !important;
      box-shadow: 0 0 14px rgba(239, 68, 68, 0.6); animation: blink 1.2s infinite alternate;
    }
    .btn-evt.btn-just-activated {
      background: #059669 !important; border-color: #34d399 !important; color: #ffffff !important;
      box-shadow: 0 0 15px rgba(52, 211, 153, 0.6); transition: none;
    }
    .btn-evt.btn-fading-out {
      background: #1e293b; border-color: rgba(255,255,255,0.12); color: #cbd5e1;
      box-shadow: none; transition: all 1.8s cubic-bezier(0.4, 0, 0.2, 1);
    }

    .state-indicator { font-size: 0.68rem; font-weight: bold; text-transform: uppercase; padding: 2px 6px; border-radius: 4px; background: rgba(0,0,0,0.3); }

    #instructions {
      position: absolute; bottom: 20px; left: 50%; transform: translateX(-50%);
      background: rgba(15, 23, 42, 0.88); border: 1px solid rgba(255, 255, 255, 0.12);
      padding: 8px 20px; border-radius: 20px; color: #94a3b8; font-size: 0.82rem; pointer-events: none; z-index: 10;
      white-space: nowrap;
    }
    #instructions span { color: #f8fafc; font-weight: bold; }
  </style>

  <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
</head>
<body>
  <div id="vignette-overlay"></div>

  <div id="hud">
    <h2>
      <span>Digital Twin</span>
      <span id="current-room-name" class="room-badge">HALLWAY</span>
    </h2>
    <div class="status-row">
      <span id="status-fire" class="badge badge-ok">Fire: Normal</span>
      <span id="status-burglar" class="badge badge-ok">Alarm: Armed</span>
      <span id="status-vent" class="badge badge-ok">Vent: Stage 1</span>
      <span id="status-hvac" class="badge badge-ok">HVAC: Idle</span>
    </div>

    <div class="sensor-grid">
      <div style="font-size:0.72rem; color:#94a3b8; font-weight:bold; margin-bottom:4px; text-transform:uppercase;">Room Telemetry:</div>
      <div class="sensor-item"><span>Temperature:</span><span id="disp-temp" class="val">--</span></div>
      <div class="sensor-item"><span>Humidity:</span><span id="disp-hum" class="val">--</span></div>
      <div class="sensor-item"><span>CO2 Level:</span><span id="disp-co2" class="val">--</span></div>
      <div class="sensor-item"><span>PIR Motion:</span><span id="disp-motion" class="val">--</span></div>
      <div class="sensor-item"><span>Smoke Detector:</span><span id="disp-smoke" class="val">--</span></div>
    </div>

    <div id="debuff-card" class="state-normal">
      <span>Player Condition:</span>
      <span id="player-condition-text">NORMAL</span>
    </div>
  </div>

  <div id="event-panel">
    <h3>Simulate Events</h3>
    <div id="action-status">Action applied</div>
    <div class="btn-grid">
      <button id="btn-fire" class="btn-evt" onclick="triggerEvent('fire', 'Kitchen Fire Simulation')">
        <span><span class="tag-icon">[FIRE]</span> Kitchen Fire & Smoke Spike</span>
        <span id="tag-fire" class="state-indicator">OFF</span>
      </button>

      <button id="btn-clear-fire" class="btn-evt" onclick="triggerEvent('clear_fire', 'Extinguish / Clear Fire')">
        <span><span class="tag-icon">[CLEAR]</span> Extinguish / Clear Fire</span>
        <span class="state-indicator">EXEC</span>
      </button>

      <button id="btn-co2" class="btn-evt" onclick="triggerEvent('co2_spike', 'Living Room CO2 Spike')">
        <span><span class="tag-icon">[CO2]</span> Living Room CO2 Spike</span>
        <span id="tag-co2" class="state-indicator">OFF</span>
      </button>

      <button id="btn-freeze" class="btn-evt" onclick="triggerEvent('freeze', 'Cold Wave Triggered')">
        <span><span class="tag-icon">[COLD]</span> Cold Wave (16&deg;C -&gt; Heat ON)</span>
        <span id="tag-freeze" class="state-indicator">EXEC</span>
      </button>

      <button id="btn-heatwave" class="btn-evt" onclick="triggerEvent('heatwave', 'Heatwave Triggered')">
        <span><span class="tag-icon">[HEAT]</span> Heatwave (28.5&deg;C -&gt; Cooling)</span>
        <span id="tag-heatwave" class="state-indicator">EXEC</span>
      </button>

      <button id="btn-arm" class="btn-evt" onclick="triggerEvent('toggle_arm', 'Alarm Arming State')">
        <span><span class="tag-icon">[ALARM]</span> Toggle Alarm Arming</span>
        <span id="tag-arm" class="state-indicator">ARMED</span>
      </button>
    </div>
  </div>

  <div id="interact-prompt"><span class="key">E</span> <span id="prompt-text">Toggle Sensor</span></div>
  <div id="unstuck-toast">Position reset to safe open floor</div>

  <div id="instructions">
    <span>W/A/S/D</span> Camera Relative | <span>SHIFT</span> Run | <span>SPACE</span> Jump | <span>E</span> Toggle Sensor | <span>U</span> Unstuck | <span>DRAG</span> Look
  </div>

  <script>
    let toastTimeout = null;

    function flashButton(btnId, actionTitle) {
      const btn = document.getElementById(btnId);
      if (!btn) return;

      btn.classList.remove('btn-fading-out');
      btn.classList.add('btn-just-activated');

      const banner = document.getElementById('action-status');
      banner.style.display = 'block';
      banner.style.opacity = '1';
      banner.innerText = `Applied: ${actionTitle}`;

      clearTimeout(toastTimeout);
      toastTimeout = setTimeout(() => {
        banner.style.opacity = '0';
        setTimeout(() => { banner.style.display = 'none'; }, 800);
      }, 2000);

      setTimeout(() => {
        btn.classList.remove('btn-just-activated');
        btn.classList.add('btn-fading-out');
      }, 100);
    }

    async function triggerEvent(type, actionTitle) {
      const btnMap = {
        'fire': 'btn-fire',
        'clear_fire': 'btn-clear-fire',
        'co2_spike': 'btn-co2',
        'freeze': 'btn-freeze',
        'heatwave': 'btn-heatwave',
        'toggle_arm': 'btn-arm'
      };
      flashButton(btnMap[type], actionTitle);

      try {
        const res = await fetch(`${window.location.origin}/api/event?type=${type}`, { method: 'POST' });
        if (!res.ok) console.error("Event trigger failed:", await res.text());
      } catch (err) {
        console.error("Network error triggering event:", err);
      }
    }

    async function toggleSensorApi(sensorId) {
      try {
        const res = await fetch(`${window.location.origin}/api/toggle-sensor?id=${sensorId}`, { method: 'POST' });
        if (!res.ok) console.error("Toggle failed:", await res.text());
      } catch (err) {
        console.error("Network error toggling sensor:", err);
      }
    }

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0f172a);
    scene.fog = new THREE.FogExp2(0x0f172a, 0.025);

    const camera = new THREE.PerspectiveCamera(65, window.innerWidth / window.innerHeight, 0.1, 100);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    document.body.appendChild(renderer.domElement);

    const ambientLight = new THREE.AmbientLight(0xffffff, 0.65);
    scene.add(ambientLight);

    const sun = new THREE.DirectionalLight(0xffedd5, 0.85);
    sun.position.set(12, 18, 10);
    sun.castShadow = true;
    sun.shadow.mapSize.width = 2048;
    sun.shadow.mapSize.height = 2048;
    scene.add(sun);

    const fireLight = new THREE.PointLight(0xff4500, 0, 8);
    fireLight.position.set(4.5, 1.2, -6.0);
    scene.add(fireLight);

    function makeTexture(type) {
      const c = document.createElement('canvas');
      c.width = 256; c.height = 256;
      const ctx = c.getContext('2d');
      if (type === 'wood') {
        ctx.fillStyle = '#b47846'; ctx.fillRect(0,0,256,256);
        ctx.fillStyle = '#8f5627';
        for (let y = 0; y < 256; y += 32) {
          ctx.fillRect(0, y, 256, 2);
          for (let x = (y % 64 === 0 ? 0 : 32); x < 256; x += 64) ctx.fillRect(x, y, 2, 32);
        }
      } else if (type === 'tile') {
        ctx.fillStyle = '#cbd5e1'; ctx.fillRect(0,0,256,256);
        ctx.strokeStyle = '#94a3b8'; ctx.lineWidth = 4;
        ctx.strokeRect(2, 2, 126, 126); ctx.strokeRect(130, 2, 126, 126);
        ctx.strokeRect(2, 130, 126, 126); ctx.strokeRect(130, 130, 126, 126);
      } else if (type === 'carpet') {
        ctx.fillStyle = '#334155'; ctx.fillRect(0,0,256,256);
        for (let i = 0; i < 300; i++) {
          ctx.fillStyle = Math.random() > 0.5 ? '#475569' : '#1e293b';
          ctx.fillRect(Math.random()*256, Math.random()*256, 3, 3);
        }
      }
      const tex = new THREE.CanvasTexture(c);
      tex.wrapS = THREE.RepeatWrapping; tex.wrapT = THREE.RepeatWrapping;
      return tex;
    }

    const texWood = makeTexture('wood'); texWood.repeat.set(4, 4);
    const texTile = makeTexture('tile'); texTile.repeat.set(4, 4);
    const texCarpet = makeTexture('carpet'); texCarpet.repeat.set(4, 4);

    const colliders = [];
    function addBox(w, h, d, x, y, z, mat, isObstacle = true) {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      mesh.position.set(x, y + h / 2, z);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      scene.add(mesh);
      if (isObstacle) {
        colliders.push(new THREE.Box3(
          new THREE.Vector3(x - w / 2, y, z - d / 2),
          new THREE.Vector3(x + w / 2, y + h, z + d / 2)
        ));
      }
      return mesh;
    }

    const wallMat = new THREE.MeshStandardMaterial({ color: 0xf1f5f9, roughness: 0.8 });
    const woodMat = new THREE.MeshStandardMaterial({ color: 0x854d0e, roughness: 0.6 });
    const darkWoodMat = new THREE.MeshStandardMaterial({ color: 0x3f2e21, roughness: 0.5 });
    const fabricMat = new THREE.MeshStandardMaterial({ color: 0x1e293b, roughness: 0.9 });
    const metalMat = new THREE.MeshStandardMaterial({ color: 0x94a3b8, metalness: 0.8, roughness: 0.2 });

    function makeFloor(x, z, tex) {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(8, 8), new THREE.MeshStandardMaterial({ map: tex }));
      m.rotation.x = -Math.PI / 2; m.position.set(x, 0, z); m.receiveShadow = true; scene.add(m);
    }
    makeFloor(-4, -4, texWood);
    makeFloor(4, -4, texTile);
    makeFloor(-4, 4, texCarpet);
    makeFloor(4, 4, texWood);

    const H = 2.8, T = 0.3;
    addBox(16.6, H, T, 0, 0, -8.15, wallMat);
    addBox(16.6, H, T, 0, 0, 8.15, wallMat);
    addBox(T, H, 16.6, -8.15, 0, 0, wallMat);
    addBox(T, H, 16.6, 8.15, 0, 0, wallMat);

    addBox(T, H, 4.5, 0, 0, -5.75, wallMat);
    addBox(T, H, 4.0, 0, 0, 0, wallMat);
    addBox(T, H, 4.5, 0, 0, 5.75, wallMat);
    addBox(4.5, H, T, -5.75, 0, 0, wallMat);
    addBox(4.5, H, T, 5.75, 0, 0, wallMat);

    // Furniture
    addBox(3.2, 0.7, 1.0, -4.5, 0, -7.2, fabricMat);
    addBox(1.0, 0.7, 2.2, -6.0, 0, -5.6, fabricMat);
    addBox(1.6, 0.4, 0.9, -4.2, 0, -5.3, darkWoodMat);
    addBox(2.6, 0.5, 0.5, -4.2, 0, -0.6, woodMat);
    addBox(2.2, 1.2, 0.1, -4.2, 0.7, -0.4, new THREE.MeshStandardMaterial({ color: 0x0284c7 }));

    addBox(3.0, 0.9, 1.2, 4.5, 0, -6.8, new THREE.MeshStandardMaterial({ color: 0xf8fafc, roughness: 0.3 }));
    addBox(0.9, 2.0, 0.9, 7.2, 0, -6.8, metalMat);
    addBox(2.0, 0.75, 1.1, 4.0, 0, -3.5, woodMat);
    addBox(0.5, 0.85, 0.5, 4.0, 0, -2.4, fabricMat);
    addBox(0.5, 0.85, 0.5, 4.0, 0, -4.6, fabricMat);

    addBox(2.2, 0.6, 2.0, -4.8, 0, 6.6, fabricMat);
    addBox(2.4, 1.2, 0.2, -4.8, 0, 7.7, darkWoodMat);
    addBox(0.6, 0.5, 0.5, -6.4, 0, 7.3, woodMat);
    addBox(0.6, 0.5, 0.5, -3.2, 0, 7.3, woodMat);
    addBox(1.2, 2.3, 2.8, -7.2, 0, 3.5, woodMat);

    addBox(2.2, 0.75, 1.0, 5.0, 0, 6.8, darkWoodMat);
    addBox(1.0, 0.5, 0.1, 5.0, 0.75, 7.1, new THREE.MeshStandardMaterial({ color: 0x38bdf8 }));
    addBox(0.6, 0.9, 0.6, 5.0, 0, 5.5, fabricMat);
    addBox(0.5, 2.2, 2.4, 7.6, 0, 3.5, woodMat);

    // 3D Fire & Smoke Simulation
    const fireGroup = new THREE.Group();
    scene.add(fireGroup);

    const flameCount = 45;
    const flameGeo = new THREE.DodecahedronGeometry(0.12, 1);
    const flames = [];

    for (let i = 0; i < flameCount; i++) {
      const mat = new THREE.MeshBasicMaterial({
        color: Math.random() > 0.4 ? 0xff4500 : 0xffaa00,
        transparent: true,
        opacity: 0.85
      });
      const mesh = new THREE.Mesh(flameGeo, mat);
      mesh.position.set(
        4.5 + (Math.random() - 0.5) * 1.2,
        0.9 + Math.random() * 0.4,
        -6.8 + (Math.random() - 0.5) * 0.6
      );
      mesh.userData = {
        baseY: 0.9,
        speedY: 1.2 + Math.random() * 1.5,
        speedX: (Math.random() - 0.5) * 0.4,
        speedZ: (Math.random() - 0.5) * 0.4,
        life: Math.random()
      };
      fireGroup.add(mesh);
      flames.push(mesh);
    }

    const smokeCount = 35;
    const smokeGeo = new THREE.SphereGeometry(0.18, 8, 8);
    const smokes = [];

    for (let i = 0; i < smokeCount; i++) {
      const mat = new THREE.MeshBasicMaterial({
        color: 0x334155,
        transparent: true,
        opacity: 0.4
      });
      const mesh = new THREE.Mesh(smokeGeo, mat);
      mesh.position.set(
        4.5 + (Math.random() - 0.5) * 1.5,
        1.5 + Math.random() * 1.2,
        -6.8 + (Math.random() - 0.5) * 1.0
      );
      mesh.userData = {
        baseY: 1.3,
        speedY: 0.6 + Math.random() * 0.7,
        life: Math.random()
      };
      fireGroup.add(mesh);
      smokes.push(mesh);
    }

    fireGroup.visible = false;

    // Falling Frost / Ice Particles
    const frostCount = 120;
    const frostGeo = new THREE.BufferGeometry();
    const frostPos = new Float32Array(frostCount * 3);
    for (let i = 0; i < frostCount * 3; i += 3) {
      frostPos[i] = (Math.random() - 0.5) * 16;
      frostPos[i+1] = Math.random() * 2.8;
      frostPos[i+2] = (Math.random() - 0.5) * 16;
    }
    frostGeo.setAttribute('position', new THREE.BufferAttribute(frostPos, 3));
    const frostMat = new THREE.PointsMaterial({
      color: 0xe0f2fe,
      size: 0.08,
      transparent: true,
      opacity: 0.0
    });
    const frostPoints = new THREE.Points(frostGeo, frostMat);
    scene.add(frostPoints);

    // CO2 Dust/Gas Particles
    const co2Count = 150;
    const co2Geo = new THREE.BufferGeometry();
    const co2Pos = new Float32Array(co2Count * 3);
    for (let i = 0; i < co2Count * 3; i += 3) {
      co2Pos[i] = (Math.random() - 0.5) * 16;
      co2Pos[i+1] = Math.random() * 2.5;
      co2Pos[i+2] = (Math.random() - 0.5) * 16;
    }
    co2Geo.setAttribute('position', new THREE.BufferAttribute(co2Pos, 3));
    const co2Mat = new THREE.PointsMaterial({
      color: 0xeab308,
      size: 0.12,
      transparent: true,
      opacity: 0.0
    });
    const co2Points = new THREE.Points(co2Geo, co2Mat);
    scene.add(co2Points);

    // Sensors
    const interactiveSensors = [];

    function createPIRSensor(id, name, room, pos, rotY) {
      const group = new THREE.Group();
      group.position.copy(pos);
      group.rotation.y = rotY;

      const base = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.28, 0.08), new THREE.MeshStandardMaterial({ color: 0xffffff }));
      const dome = new THREE.Mesh(new THREE.SphereGeometry(0.08, 16, 16), new THREE.MeshStandardMaterial({ color: 0xe2e8f0, roughness: 0.2 }));
      dome.position.z = 0.05;
      const led = new THREE.Mesh(new THREE.SphereGeometry(0.02, 8, 8), new THREE.MeshBasicMaterial({ color: 0x22c55e }));
      led.position.set(0, 0.09, 0.05);

      group.add(base); group.add(dome); group.add(led);

      const coneHeight = 3.6;
      const coneRadius = 2.4;
      const coneGeo = new THREE.ConeGeometry(coneRadius, coneHeight, 20, 1, true);
      coneGeo.translate(0, -coneHeight / 2, 0);
      coneGeo.rotateX(-Math.PI / 2.3);

      const coneMat = new THREE.MeshBasicMaterial({
        color: 0x38bdf8,
        transparent: true,
        opacity: 0.18,
        wireframe: true,
        side: THREE.DoubleSide
      });
      const cone = new THREE.Mesh(coneGeo, coneMat);
      cone.position.set(0, 0, 0.1);
      group.add(cone);

      scene.add(group);

      const sensorObj = {
        id, name, room, type: "pir",
        worldPos: pos, meshGroup: group,
        led, cone, coneMat,
        enabled: true, active: false
      };
      interactiveSensors.push(sensorObj);
      return sensorObj;
    }

    function createSmokeDetector(id, name, room, pos) {
      const group = new THREE.Group();
      group.position.copy(pos);

      const disc = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 0.06, 24), new THREE.MeshStandardMaterial({ color: 0xf8fafc }));
      disc.position.y = -0.03;
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.18, 0.015, 8, 24), new THREE.MeshStandardMaterial({ color: 0x94a3b8 }));
      ring.rotation.x = Math.PI / 2; ring.position.y = -0.06;
      const led = new THREE.Mesh(new THREE.SphereGeometry(0.025, 8, 8), new THREE.MeshBasicMaterial({ color: 0x22c55e }));
      led.position.set(0.14, -0.06, 0);

      group.add(disc); group.add(ring); group.add(led);

      const fieldGeo = new THREE.CylinderGeometry(2.0, 2.0, 2.4, 20, 1, true);
      const fieldMat = new THREE.MeshBasicMaterial({
        color: 0xef4444,
        transparent: true,
        opacity: 0.12,
        wireframe: true,
        side: THREE.DoubleSide
      });
      const field = new THREE.Mesh(fieldGeo, fieldMat);
      field.position.y = -1.2;
      group.add(field);

      scene.add(group);

      const sensorObj = {
        id, name, room, type: "smoke",
        worldPos: pos, meshGroup: group,
        led, cone: field, coneMat: fieldMat,
        enabled: true, active: false
      };
      interactiveSensors.push(sensorObj);
      return sensorObj;
    }

    function createClimateSensor(id, name, room, pos) {
      const group = new THREE.Group();
      group.position.copy(pos);

      const box = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.18, 0.04), new THREE.MeshStandardMaterial({ color: 0xf1f5f9 }));
      const screen = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 0.08), new THREE.MeshBasicMaterial({ color: 0x0284c7 }));
      screen.position.z = 0.021;
      const led = new THREE.Mesh(new THREE.SphereGeometry(0.015, 8, 8), new THREE.MeshBasicMaterial({ color: 0x22c55e }));
      led.position.set(0, 0.065, 0.022);

      group.add(box); group.add(screen); group.add(led);
      scene.add(group);

      const sensorObj = {
        id, name, room, type: "climate",
        worldPos: pos, meshGroup: group,
        led, cone: null, coneMat: null,
        enabled: true, active: false
      };
      interactiveSensors.push(sensorObj);
      return sensorObj;
    }

    createPIRSensor("living_room_pir", "Living Room PIR", "living_room", new THREE.Vector3(-0.4, 2.2, -7.9), 0);
    createClimateSensor("living_room_climate", "Living Room Climate/CO2", "living_room", new THREE.Vector3(-4.0, 1.4, -7.95));

    createSmokeDetector("kitchen_smoke", "Kitchen Smoke Detector", "kitchen", new THREE.Vector3(4.5, 2.75, -5.5));
    createClimateSensor("kitchen_climate", "Kitchen Climate", "kitchen", new THREE.Vector3(7.95, 1.5, -4.0));

    createPIRSensor("bedroom_pir", "Bedroom PIR", "bedroom", new THREE.Vector3(-7.9, 2.2, 0.4), Math.PI / 2);
    createClimateSensor("bedroom_climate", "Bedroom Thermostat", "bedroom", new THREE.Vector3(-7.95, 1.4, 5.0));

    createPIRSensor("office_pir", "Office PIR", "office", new THREE.Vector3(0.4, 2.2, 7.9), Math.PI);
    createClimateSensor("office_climate", "Office Climate", "office", new THREE.Vector3(7.95, 1.5, 5.0));

    // Player rig
    const character = new THREE.Group();
    scene.add(character);

    const skinMat = new THREE.MeshStandardMaterial({ color: 0xfbbf24, roughness: 0.4 });
    const clothesMat = new THREE.MeshStandardMaterial({ color: 0x2563eb, roughness: 0.5 });
    const pantsMat = new THREE.MeshStandardMaterial({ color: 0x1e293b, roughness: 0.6 });

    const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.18, 0.65, 12), clothesMat);
    torso.position.y = 1.1; torso.castShadow = true; character.add(torso);

    const head = new THREE.Mesh(new THREE.SphereGeometry(0.16, 16, 16), skinMat);
    head.position.y = 1.6; head.castShadow = true; character.add(head);

    function createLimb(w, h, mat, px, py, pz) {
      const pivot = new THREE.Group();
      pivot.position.set(px, py, pz);
      const mesh = new THREE.Mesh(new THREE.CylinderGeometry(w, w*0.8, h, 8), mat);
      mesh.position.y = -h / 2;
      mesh.castShadow = true;
      pivot.add(mesh);
      character.add(pivot);
      return pivot;
    }

    const leftLeg = createLimb(0.08, 0.7, pantsMat, -0.12, 0.75, 0);
    const rightLeg = createLimb(0.08, 0.7, pantsMat, 0.12, 0.75, 0);
    const leftArm = createLimb(0.06, 0.6, clothesMat, -0.32, 1.35, 0);
    const rightArm = createLimb(0.06, 0.6, clothesMat, 0.32, 1.35, 0);

    const playerRadius = 0.35;
    const SAFE_SPAWN = new THREE.Vector3(-3.0, 0, -3.0);
    const playerPos = SAFE_SPAWN.clone();
    const playerVel = new THREE.Vector3();
    let onFloor = true;

    const keys = {};
    let nearestSensor = null;

    function resetToSafePosition() {
      playerPos.copy(SAFE_SPAWN);
      playerVel.set(0, 0, 0);
      cameraAngle.yaw = 0;
      cameraAngle.pitch = 0.35;
      character.position.copy(playerPos);
      
      const toast = document.getElementById("unstuck-toast");
      toast.style.display = "block";
      setTimeout(() => { toast.style.display = "none"; }, 2000);
    }

    window.addEventListener('keydown', (e) => {
      keys[e.code] = true;
      if (e.code === 'KeyE' && nearestSensor) {
        toggleSensorApi(nearestSensor.id);
      }
      if (e.code === 'KeyU') {
        resetToSafePosition();
      }
    });
    window.addEventListener('keyup', (e) => { keys[e.code] = false; });

    let isMouseDown = false;
    let cameraAngle = { yaw: 0, pitch: 0.35 };
    window.addEventListener('mousedown', () => { isMouseDown = true; });
    window.addEventListener('mouseup', () => { isMouseDown = false; });
    window.addEventListener('mousemove', (e) => {
      if (isMouseDown) {
        cameraAngle.yaw -= e.movementX * 0.003;
        cameraAngle.pitch = Math.max(0.1, Math.min(1.1, cameraAngle.pitch + e.movementY * 0.003));
      }
    });

    let walkCycle = 0;

    function updatePhysics(dt) {
      const currentRoom = getCurrentRoom(playerPos.x, playerPos.z);
      let ambientTemp = 21.0;
      let ambientCo2 = 600;

      if (latestTelemetry && currentRoom !== "hallway" && latestTelemetry.houseState[currentRoom]) {
        ambientTemp = latestTelemetry.houseState[currentRoom].temperature;
        ambientCo2 = latestTelemetry.houseState[currentRoom].co2;
      }

      const isCold = ambientTemp <= 16.5;
      const isHot = ambientTemp >= 27.0 || (latestTelemetry && latestTelemetry.subsystems.fireAlarm.active === 1);
      const isHighCo2 = ambientCo2 >= 1100;

      let baseSpeed = 3.8;
      let sprintSpeed = 7.5;

      if (isHighCo2) {
        baseSpeed = 1.8;
        sprintSpeed = 3.2;
      } else if (isCold) {
        baseSpeed = 2.0;
        sprintSpeed = 3.8;
      } else if (isHot) {
        baseSpeed = 2.4;
        sprintSpeed = 4.2;
      }

      const isRunning = keys['ShiftLeft'] || keys['ShiftRight'];
      const speed = isRunning ? sprintSpeed : baseSpeed;

      let forwardInput = 0;
      let strafeInput = 0;

      if (keys['KeyW'] || keys['ArrowUp']) forwardInput += 1;
      if (keys['KeyS'] || keys['ArrowDown']) forwardInput -= 1;
      if (keys['KeyA'] || keys['ArrowLeft']) strafeInput -= 1;
      if (keys['KeyD'] || keys['ArrowRight']) strafeInput += 1;

      const inputLen = Math.hypot(forwardInput, strafeInput);
      if (inputLen > 0) {
        forwardInput /= inputLen;
        strafeInput /= inputLen;

        const camForward = new THREE.Vector3(-Math.sin(cameraAngle.yaw), 0, -Math.cos(cameraAngle.yaw));
        const camRight = new THREE.Vector3(Math.cos(cameraAngle.yaw), 0, -Math.sin(cameraAngle.yaw));

        const moveDir = new THREE.Vector3()
          .addScaledVector(camForward, forwardInput)
          .addScaledVector(camRight, strafeInput)
          .normalize();

        playerVel.x = moveDir.x * speed;
        playerVel.z = moveDir.z * speed;

        const targetAngle = Math.atan2(moveDir.x, moveDir.z);
        character.rotation.y = targetAngle;

        walkCycle += dt * (isRunning ? 18 : 10) * (isCold || isHighCo2 ? 0.7 : 1.0);
        const swing = Math.sin(walkCycle) * (isCold ? 0.35 : 0.6);
        leftLeg.rotation.x = swing;
        rightLeg.rotation.x = -swing;
        leftArm.rotation.x = -swing;
        rightArm.rotation.x = swing;
        torso.position.y = 1.1 + Math.abs(Math.sin(walkCycle * 2)) * 0.04;
      } else {
        playerVel.x = 0;
        playerVel.z = 0;
        leftLeg.rotation.x = 0;
        rightLeg.rotation.x = 0;
        leftArm.rotation.x = 0;
        rightArm.rotation.x = 0;
        torso.position.y = 1.1 + Math.sin(Date.now() * 0.003) * 0.015;
      }

      if (isHighCo2) {
        const coughJerk = Math.sin(Date.now() * 0.015) > 0.7 ? 0.25 : 0;
        head.rotation.x = 0.35 + coughJerk;
        torso.rotation.x = 0.2 + coughJerk * 0.5;
        torso.position.x = 0;
      } else if (isCold) {
        const shiver = (Math.random() - 0.5) * 0.035;
        torso.position.x = shiver;
        head.position.x = -shiver;
        torso.rotation.x = 0.15;
      } else if (isHot) {
        torso.position.x = 0;
        head.position.x = 0;
        torso.rotation.x = 0.32;
        head.rotation.x = 0.25;
      } else {
        torso.position.x = 0;
        head.position.x = 0;
        torso.rotation.x = 0;
        head.rotation.x = 0;
      }

      if (onFloor && keys['Space']) {
        playerVel.y = isHot || isHighCo2 ? 4.2 : 6.0;
        onFloor = false;
      }
      playerVel.y -= 19.8 * dt;

      const nextX = playerPos.x + playerVel.x * dt;
      const nextZ = playerPos.z + playerVel.z * dt;
      const nextY = playerPos.y + playerVel.y * dt;

      let canMoveX = true;
      for (const box of colliders) {
        if (nextX + playerRadius > box.min.x && nextX - playerRadius < box.max.x &&
            playerPos.z + playerRadius > box.min.z && playerPos.z - playerRadius < box.max.z &&
            playerPos.y + 1.5 > box.min.y && playerPos.y < box.max.y) {
          canMoveX = false;
          break;
        }
      }
      if (canMoveX) playerPos.x = nextX;

      let canMoveZ = true;
      for (const box of colliders) {
        if (playerPos.x + playerRadius > box.min.x && playerPos.x - playerRadius < box.max.x &&
            nextZ + playerRadius > box.min.z && nextZ - playerRadius < box.max.z &&
            playerPos.y + 1.5 > box.min.y && playerPos.y < box.max.y) {
          canMoveZ = false;
          break;
        }
      }
      if (canMoveZ) playerPos.z = nextZ;

      if (nextY <= 0) {
        playerPos.y = 0;
        playerVel.y = 0;
        onFloor = true;
      } else {
        playerPos.y = nextY;
      }

      character.position.copy(playerPos);

      const dist = 3.6;
      const camH = Math.sin(cameraAngle.pitch) * dist;
      const camR = Math.cos(cameraAngle.pitch) * dist;

      camera.position.set(
        playerPos.x + Math.sin(cameraAngle.yaw) * camR,
        playerPos.y + 1.6 + camH,
        playerPos.z + Math.cos(cameraAngle.yaw) * camR
      );
      camera.lookAt(playerPos.x, playerPos.y + 1.3, playerPos.z);

      nearestSensor = null;
      let minDist = 1.8;
      for (const s of interactiveSensors) {
        const d = playerPos.distanceTo(s.worldPos);
        if (d < minDist) {
          minDist = d;
          nearestSensor = s;
        }
      }

      const promptEl = document.getElementById("interact-prompt");
      const promptText = document.getElementById("prompt-text");
      if (nearestSensor) {
        promptEl.style.display = "block";
        promptText.innerText = nearestSensor.enabled ? `Turn OFF ${nearestSensor.name}` : `Turn ON ${nearestSensor.name}`;
      } else {
        promptEl.style.display = "none";
      }
    }

    function getCurrentRoom(x, z) {
      if (x < -0.3 && z < -0.3) return "living_room";
      if (x > 0.3 && z < -0.3) return "kitchen";
      if (x < -0.3 && z > 0.3) return "bedroom";
      if (x > 0.3 && z > 0.3) return "office";
      return "hallway";
    }

    let latestTelemetry = null;
    const socket = new WebSocket(`ws://${location.host}`);
    socket.onmessage = (event) => {
      latestTelemetry = JSON.parse(event.data);
      updateSensorVisuals();
      updateHUD();
    };

    function updateSensorVisuals() {
      if (!latestTelemetry) return;
      const { houseState, sensorStatus, activeEvents } = latestTelemetry;

      const btnFire = document.getElementById('btn-fire');
      const tagFire = document.getElementById('tag-fire');
      if (activeEvents?.fire) {
        btnFire.classList.add('btn-persistent-fire');
        tagFire.innerText = 'ACTIVE';
        fireGroup.visible = true;
        fireLight.intensity = 2.5 + Math.random() * 1.5;
      } else {
        btnFire.classList.remove('btn-persistent-fire');
        tagFire.innerText = 'OFF';
        fireGroup.visible = false;
        fireLight.intensity = 0;
      }

      const btnCo2 = document.getElementById('btn-co2');
      const tagCo2 = document.getElementById('tag-co2');
      if (activeEvents?.co2_spike) {
        btnCo2.classList.add('btn-persistent-co2');
        tagCo2.innerText = 'SPIKED';
      } else {
        btnCo2.classList.remove('btn-persistent-co2');
        tagCo2.innerText = 'NORMAL';
      }

      const btnArm = document.getElementById('btn-arm');
      const tagArm = document.getElementById('tag-arm');
      if (activeEvents?.alarmArmed) {
        btnArm.classList.add('btn-persistent-active');
        tagArm.innerText = 'ARMED';
      } else {
        btnArm.classList.remove('btn-persistent-active');
        tagArm.innerText = 'DISARMED';
      }

      interactiveSensors.forEach(s => {
        const isEnabled = sensorStatus[s.id] !== false;
        s.enabled = isEnabled;

        if (!isEnabled) {
          s.led.material.color.setHex(0x64748b);
          if (s.cone) s.cone.visible = false;
          return;
        }

        if (s.cone) s.cone.visible = true;

        if (s.type === "pir") {
          const hasMotion = houseState[s.room] && houseState[s.room].motion === 1;
          if (hasMotion) {
            s.led.material.color.setHex(0xf59e0b);
            if (s.coneMat) {
              s.coneMat.color.setHex(0xf59e0b);
              s.coneMat.opacity = 0.45;
            }
          } else {
            s.led.material.color.setHex(0x22c55e);
            if (s.coneMat) {
              s.coneMat.color.setHex(0x38bdf8);
              s.coneMat.opacity = 0.18;
            }
          }
        } else if (s.type === "smoke") {
          const isSmoke = houseState[s.room] && houseState[s.room].smoke === 1;
          if (isSmoke) {
            s.led.material.color.setHex(0xef4444);
            if (s.coneMat) {
              s.coneMat.color.setHex(0xef4444);
              s.coneMat.opacity = 0.6;
            }
          } else {
            s.led.material.color.setHex(0x22c55e);
            if (s.coneMat) {
              s.coneMat.color.setHex(0x94a3b8);
              s.coneMat.opacity = 0.1;
            }
          }
        } else if (s.type === "climate") {
          s.led.material.color.setHex(0x38bdf8);
        }
      });
    }

    function updateHUD() {
      if (!latestTelemetry) return;
      const { houseState, subsystems, sensorStatus } = latestTelemetry;
      const room = getCurrentRoom(playerPos.x, playerPos.z);

      document.getElementById("current-room-name").innerText = room.replace("_", " ").toUpperCase();

      let currentRoomTemp = 21.0;
      let currentRoomCo2 = 600;

      if (room !== "hallway" && houseState[room]) {
        const s = houseState[room];
        currentRoomTemp = s.temperature;
        currentRoomCo2 = s.co2;
        const isClimateOn = sensorStatus[`${room}_climate`] !== false;
        const isPirOn = sensorStatus[`${room}_pir`] !== false;

        document.getElementById("disp-temp").innerText = isClimateOn ? `${s.temperature} \u00B0C` : "Sensor Off";
        document.getElementById("disp-hum").innerText = isClimateOn ? `${s.humidity} %` : "Sensor Off";
        document.getElementById("disp-co2").innerText = isClimateOn ? `${s.co2} ppm` : "Sensor Off";
        document.getElementById("disp-motion").innerText = isPirOn ? (s.motion ? "MOTION DETECTED" : "Clear") : "Sensor Off";
        document.getElementById("disp-smoke").innerText = s.smoke ? "SMOKE ALARM!" : "Normal";
      } else {
        document.getElementById("disp-temp").innerText = "Hallway / Transit";
        document.getElementById("disp-hum").innerText = "--";
        document.getElementById("disp-co2").innerText = "--";
        document.getElementById("disp-motion").innerText = "--";
        document.getElementById("disp-smoke").innerText = "Normal";
      }

      const overlay = document.getElementById("vignette-overlay");
      const debuffCard = document.getElementById("debuff-card");
      const conditionText = document.getElementById("player-condition-text");

      if (currentRoomCo2 >= 1100) {
        overlay.className = "co2-vignette";
        co2Mat.opacity = 0.7;
        frostMat.opacity = 0.0;
        debuffCard.className = "state-co2";
        conditionText.innerText = "SUFFOCATING / CO2 HAZARD (COUGHING)";
      } else if (currentRoomTemp <= 16.5) {
        overlay.className = "cold-vignette";
        frostMat.opacity = 0.75;
        co2Mat.opacity = 0.0;
        debuffCard.className = "state-cold";
        conditionText.innerText = "SHIVERING / JOINT STIFFNESS (SLOW)";
      } else if (currentRoomTemp >= 27.0 || subsystems.fireAlarm.active === 1) {
        overlay.className = "heat-vignette";
        frostMat.opacity = 0.0;
        co2Mat.opacity = 0.0;
        debuffCard.className = "state-hot";
        conditionText.innerText = "HEAT EXHAUSTION / SLUGGISH";
      } else {
        overlay.className = "";
        frostMat.opacity = 0.0;
        co2Mat.opacity = 0.0;
        debuffCard.className = "state-normal";
        conditionText.innerText = "NORMAL CONDITION";
      }

      const fireBadge = document.getElementById("status-fire");
      if (subsystems.fireAlarm.active === 1) {
        fireBadge.className = "badge badge-danger";
        fireBadge.innerText = `FIRE: ${subsystems.fireAlarm.room.toUpperCase()}`;
      } else {
        fireBadge.className = "badge badge-ok";
        fireBadge.innerText = "Fire: Normal";
      }

      const burglarBadge = document.getElementById("status-burglar");
      if (subsystems.burglarAlarm.active === 1) {
        burglarBadge.className = "badge badge-danger";
        burglarBadge.innerText = `ALARM: ${subsystems.burglarAlarm.detectedRooms.join(", ")}`;
      } else {
        burglarBadge.className = "badge badge-ok";
        burglarBadge.innerText = subsystems.alarmArmed ? "Alarm: Armed" : "Alarm: Disarmed";
      }

      const ventBadge = document.getElementById("status-vent");
      ventBadge.innerText = `Vent: Stage ${subsystems.ventilation.level}`;

      const hvacBadge = document.getElementById("status-hvac");
      if (subsystems.hvac.heatingActive) {
        hvacBadge.className = "badge badge-warn";
        hvacBadge.innerText = "HVAC: Heating";
      } else if (subsystems.hvac.coolingActive) {
        hvacBadge.className = "badge badge-warn";
        hvacBadge.innerText = "HVAC: Cooling";
      } else {
        hvacBadge.className = "badge badge-ok";
        hvacBadge.innerText = "HVAC: Standby";
      }
    }

    let lastTime = performance.now();

    function animate() {
      requestAnimationFrame(animate);
      const now = performance.now();
      const dt = Math.min(0.05, (now - lastTime) / 1000);
      lastTime = now;

      if (fireGroup.visible) {
        flames.forEach(f => {
          f.position.y += f.userData.speedY * dt;
          f.position.x += f.userData.speedX * dt;
          f.position.z += f.userData.speedZ * dt;
          f.scale.multiplyScalar(0.965);
          if (f.position.y > f.userData.baseY + 1.2 || f.scale.x < 0.1) {
            f.position.set(
              4.5 + (Math.random() - 0.5) * 1.2,
              f.userData.baseY,
              -6.8 + (Math.random() - 0.5) * 0.6
            );
            f.scale.set(1, 1, 1);
          }
        });

        smokes.forEach(s => {
          s.position.y += s.userData.speedY * dt;
          s.scale.multiplyScalar(1.018);
          s.material.opacity *= 0.985;
          if (s.position.y > 2.7 || s.material.opacity < 0.05) {
            s.position.set(
              4.5 + (Math.random() - 0.5) * 1.5,
              s.userData.baseY,
              -6.8 + (Math.random() - 0.5) * 1.0
            );
            s.scale.set(1, 1, 1);
            s.material.opacity = 0.4;
          }
        });
      }

      if (frostMat.opacity > 0.01) {
        const positions = frostGeo.attributes.position.array;
        for (let i = 1; i < frostCount * 3; i += 3) {
          positions[i] -= 0.6 * dt;
          if (positions[i] < 0) positions[i] = 2.8;
        }
        frostGeo.attributes.position.needsUpdate = true;
      }

      if (co2Mat.opacity > 0.01) {
        const cPositions = co2Geo.attributes.position.array;
        for (let i = 1; i < co2Count * 3; i += 3) {
          cPositions[i] -= 0.25 * dt;
          cPositions[i-1] += Math.sin(Date.now() * 0.001 + i) * 0.005;
          if (cPositions[i] < 0.1) cPositions[i] = 2.2;
        }
        co2Geo.attributes.position.needsUpdate = true;
      }

      updatePhysics(dt);
      updateHUD();
      renderer.render(scene, camera);
    }
    animate();

    window.addEventListener('resize', () => {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    });
  </script>
</body>
</html>
'@
[System.IO.File]::WriteAllText("$ProjectDir\app\public\index.html", $appIndexHtml, $Utf8NoBom)

# ------------------------------------------------------------------------------
# 8. Node.js App Dockerfile
# ------------------------------------------------------------------------------
$dockerfile = @'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm install
COPY src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY --from=builder /app/dist ./dist
COPY public ./public
EXPOSE 3000
CMD ["npm", "start"]
'@
[System.IO.File]::WriteAllText("$ProjectDir\app\Dockerfile", $dockerfile, $Utf8NoBom)

# ------------------------------------------------------------------------------
# 9. Docker Compose Configuration
# ------------------------------------------------------------------------------
$dockerComposeContent = @"
services:
  emqx:
    image: emqx/emqx:5.8.0
    container_name: smarthouse-broker
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "8083:8083"
      - "$($emqxPort):18083"
    environment:
      - EMQX_DASHBOARD__DEFAULT_USERNAME=admin
      - EMQX_DASHBOARD__DEFAULT_PASSWORD=public
    networks:
      - smarthouse-net

  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: smarthouse-homeassistant
    restart: unless-stopped
    ports:
      - "$($haPort):8123"
    volumes:
      - ./homeassistant/config:/config
    environment:
      - TZ=Europe/Oslo
    depends_on:
      - emqx
    networks:
      - smarthouse-net

  zigbee2mqtt:
    image: koenkk/zigbee2mqtt:latest
    container_name: smarthouse-bridge
    restart: unless-stopped
    ports:
      - "$($z2mPort):8080"
    volumes:
      - ./zigbee2mqtt/data:/app/data
    environment:
      - TZ=Europe/Oslo
    depends_on:
      - emqx
    networks:
      - smarthouse-net

  app:
    build:
      context: ./app
      dockerfile: Dockerfile
    container_name: smarthouse-app
    restart: unless-stopped
    ports:
      - "3000:3000"
    depends_on:
      - emqx
    networks:
      - smarthouse-net

  postgres-zabbix:
    image: postgres:16-alpine
    container_name: zabbix-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_password
      POSTGRES_DB: zabbix
    volumes:
      - zabbix-db-data:/var/lib/postgresql/data
    networks:
      - smarthouse-net

  zabbix-server:
    image: zabbix/zabbix-server-pgsql:alpine-7.0-latest
    container_name: zabbix-server
    restart: unless-stopped
    ports:
      - "10051:10051"
    environment:
      DB_SERVER_HOST: postgres-zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_password
      POSTGRES_DB: zabbix
    depends_on:
      - postgres-zabbix
    networks:
      - smarthouse-net

  zabbix-web:
    image: zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest
    container_name: zabbix-web
    restart: unless-stopped
    ports:
      - "$($zbxPort):8080"
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: postgres-zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_password
      POSTGRES_DB: zabbix
      PHP_TZ: Europe/Oslo
    depends_on:
      - postgres-zabbix
      - zabbix-server
    networks:
      - smarthouse-net

  zabbix-agent2:
    image: zabbix/zabbix-agent2:alpine-7.0-latest
    container_name: zabbix-agent2
    restart: unless-stopped
    privileged: true
    user: root
    environment:
      ZBX_HOSTNAME: "Docker-Desktop-Host"
      ZBX_SERVER: zabbix-server
      ZBX_SERVER_ACTIVE: zabbix-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - zabbix-server
    networks:
      - smarthouse-net

networks:
  smarthouse-net:
    driver: bridge

volumes:
  zabbix-db-data:
"@
[System.IO.File]::WriteAllText("$ProjectDir\docker-compose.yml", $dockerComposeContent, $Utf8NoBom)

# ------------------------------------------------------------------------------
# 10. Build and Start Stack
# ------------------------------------------------------------------------------
Write-Host "==> Building and deploying smart house stack..." -ForegroundColor Green
Set-Location -Path $ProjectDir

& docker compose down --remove-orphans
& docker compose up -d --build
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker compose up failed during deployment."
    exit 1
}

Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host " All Services Deployed Successfully!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "  * 3D Digital Twin (Direct)       : http://localhost:3000"
Write-Host "  * Home Assistant Portal          : http://localhost:$haPort"
Write-Host "  * EMQX Broker Web Console        : http://localhost:$emqxPort (Login: admin / public)"
Write-Host "  * Zabbix 7.0 Web UI              : http://localhost:$zbxPort (Login: Admin / zabbix)"
Write-Host "  * Zigbee2MQTT Frontend           : http://localhost:$z2mPort"
