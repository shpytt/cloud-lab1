import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8000').replace(/\/$/, '');
const VUS = Number(__ENV.VUS || 60);
const THINK = Number(__ENV.THINK || 0.3);
const RAMP_UP = __ENV.RAMP_UP || '3m';
const STEADY = __ENV.STEADY || '5m';
const RAMP_DOWN = __ENV.RAMP_DOWN || '2m';
const DEVICES = 20;

const cacheHitRate = new Rate('cache_hit_rate');

function trackCache(r) {
  const x = r.headers['X-Cache'];
  if (x === 'HIT' || x === 'MISS') cacheHitRate.add(x === 'HIT');
}

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
    http_req_failed: ['rate<0.01'],
    'http_req_duration{name:POST /devices/{id}/readings}': ['p(95)>=0'],
    'http_req_duration{name:GET /devices}': ['p(95)>=0'],
    'http_req_duration{name:GET /devices/{id}}': ['p(95)>=0'],
    'http_req_duration{name:GET /devices/{id}/readings}': ['p(95)>=0'],
  },
};

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
  trackCache(r);
  sleep(THINK);
}

function getDevice(id) {
  const r = http.get(`${BASE_URL}/devices/${id}`, { tags: { name: 'GET /devices/{id}' } });
  check(r, { 'device 200': (x) => x.status === 200 });
  trackCache(r);
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

  listDevices();
  getDevice(id);
  listReadings(id, newId);
  listDevices();
  getDevice(id);
  listReadings(id, null);
  listDevices();
  getDevice(id);
  listReadings(id, null);
}
