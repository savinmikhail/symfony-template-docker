import assert from 'node:assert/strict'
import test from 'node:test'
import { auditFailures } from './audit-exception.mjs'
const url = 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm'
const lock = { packages: { 'node_modules/braces': { dev: true, version: '3.0.3' } } }
const now = Date.parse('2026-10-12T00:00:00Z')
const report = () => ({ metadata: { vulnerabilities: {} }, vulnerabilities: { braces: { severity: 'high', nodes: ['node_modules/braces'], via: [{ name: 'braces', severity: 'high', url }] }, parent: { severity: 'high', via: ['braces'] } } })
test('only approved dev advisory and dependency chain pass', () => assert.deepEqual(auditFailures(report(), lock, now), []))
test('other critical advisory blocks', () => { const r = report(); r.vulnerabilities.braces.via.push({ severity: 'critical', url: 'other' }); assert.deepEqual(auditFailures(r, lock, now), ['other']) })
test('exception expires', () => assert.deepEqual(auditFailures(report(), lock, Date.parse('2026-11-08T00:00:00Z')), [url]))
test('production dependency blocks', () => assert.deepEqual(auditFailures(report(), { packages: { 'node_modules/braces': { version: '3.0.3' } } }, now), [url]))
test('malformed and unsuccessful audits fail closed', () => { assert.throws(() => auditFailures({ error: {} }, lock, now)); const r = report(); r.vulnerabilities.parent.via = ['missing']; assert.throws(() => auditFailures(r, lock, now)) })
test('dependency cycles fail closed', () => { const r = report(); r.vulnerabilities.parent.via = ['parent']; assert.throws(() => auditFailures(r, lock, now)) })
test('same advisory upgraded to critical blocks', () => { const r = report(); r.vulnerabilities.braces.via[0].severity = 'critical'; assert.deepEqual(auditFailures(r, lock, now), [url]) })
test('unknown advisory severity fails closed', () => { const r = report(); r.vulnerabilities.braces.via[0].severity = 'unknown'; assert.throws(() => auditFailures(r, lock, now)) })
