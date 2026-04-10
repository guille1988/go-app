import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    constant_load: {
      executor: 'constant-arrival-rate',
      rate: 1000,
      timeUnit: '1s',
      duration: '1m',
      preAllocatedVUs: 200,
      maxVUs: 1000,
    },
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
