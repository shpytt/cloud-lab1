// Навантажувальний сценарій: профіль «мало записів, багато читань».
// Одна ітерація = 1 запис + 9 читань.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8000').replace(/\/$/, '');
const VUS = Number(__ENV.VUS || 40);          // N користувачів на сталому навантаженні
const THINK = Number(__ENV.THINK || 0.3);     // пауза між запитами, с
const RAMP_UP = __ENV.RAMP_UP || '2m';        // фаза 1: наростання 0 -> N
const STEADY = __ENV.STEADY || '5m';          // фаза 2: стале навантаження
const RAMP_DOWN = __ENV.RAMP_DOWN || '2m';    // фаза 3: спад N -> 0
const DEVICES = 20;                           // скільки пристроїв використовує тест

const JSON_HEADERS = { 'Content-Type': 'application/json' };

export const options = {
  scenarios: {
    read_heavy: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: RAMP_UP, target: VUS },
        { duration: STEADY, target: VUS },
        { duration: RAMP_DOWN, target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
  thresholds: {
    http_req_failed: ['rate<0.01'], // частка помилок менша за 1%
    // Пороги нижче потрібні лише для того, щоб у звіті була латентність окремо по кожній операції
    'http_req_duration{name:POST /devices/{id}/readings}': ['p(95)>=0'],
    'http_req_duration{name:GET /devices}': ['p(95)>=0'],
    'http_req_duration{name:GET /devices/{id}}': ['p(95)>=0'],
    'http_req_duration{name:GET /devices/{id}/readings}': ['p(95)>=0'],
  },
};

// Виконується один раз перед тестом: гарантує, що в базі є DEVICES пристроїв
export function setup() {
  const res = http.get(`${BASE_URL}/devices`);
  if (res.status !== 200) {
    throw new Error(`Сервіс недоступний: GET /devices -> ${res.status}`);
  }
  const ids = res.json().map((d) => d.id).slice(0, DEVICES);
  for (let i = ids.length; i < DEVICES; i++) {
    const created = http.post(
      `${BASE_URL}/devices`,
      JSON.stringify({ name: `loadtest-sensor-${i + 1}`, location: `room-${i + 1}` }),
      { headers: JSON_HEADERS },
    );
    ids.push(created.json('id'));
  }
  return { ids };
}

function listDevices() {
  const r = http.get(`${BASE_URL}/devices`, { tags: { name: 'GET /devices' } });
  check(r, { 'list devices 200': (x) => x.status === 200 });
  sleep(THINK);
}

function getDevice(id) {
  const r = http.get(`${BASE_URL}/devices/${id}`, { tags: { name: 'GET /devices/{id}' } });
  check(r, { 'device 200': (x) => x.status === 200 });
  sleep(THINK);
}

function listReadings(id, expectReadingId) {
  const r = http.get(`${BASE_URL}/devices/${id}/readings?limit=50`, {
    tags: { name: 'GET /devices/{id}/readings' },
  });
  check(r, { 'readings 200': (x) => x.status === 200 });
  if (expectReadingId !== null && r.status === 200) {
    check(r, {
      'new reading is visible': (x) => x.json().some((row) => row.id === expectReadingId),
    });
  }
  sleep(THINK);
}

export default function (data) {
  const id = data.ids[Math.floor(Math.random() * data.ids.length)];

  // ---- 1 операція запису ----
  const body = JSON.stringify({
    temperature: Math.round((15 + Math.random() * 15) * 10) / 10,
    humidity: Math.round((30 + Math.random() * 40) * 10) / 10,
  });
  const w = http.post(`${BASE_URL}/devices/${id}/readings`, body, {
    headers: JSON_HEADERS,
    tags: { name: 'POST /devices/{id}/readings' },
  });
  check(w, { 'write accepted (201/202)': (x) => x.status === 201 || x.status === 202 });
  const newId = w.status === 201 ? w.json('id') : null;
  sleep(THINK);

  // ---- 9 операцій читання ----
  listDevices();
  getDevice(id);
  listReadings(id, newId); // включно зі щойно створеним показником
  listDevices();
  getDevice(id);
  listReadings(id, null);
  listDevices();
  getDevice(id);
  listReadings(id, null);
}
