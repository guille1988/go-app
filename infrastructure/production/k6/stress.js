import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    burst: {
      executor: 'shared-iterations',
      vus: 500,
      iterations: 500000,
      maxDuration: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.05'],
  },
};

export default function () {
  const res = http.post(
    'http://ingress-nginx-controller.ingress-nginx/api/stress',
    JSON.stringify({ email: 'stress@test.com', name: 'Stress Test' }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'status is 202': (r) => r.status === 202 });
}
