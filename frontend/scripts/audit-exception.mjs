import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const advisoryUrl = 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm'
const expiresAt = Date.parse('2026-11-08T00:00:00Z')

export function auditFailures(report, lock, now = Date.now()) {
  if (report.error || !report.metadata?.vulnerabilities || !report.vulnerabilities || !lock.packages) {
    throw new Error('Incomplete npm audit or lockfile')
  }
  const failures = new Set()
  function visit(name, path = new Set()) {
    const item = report.vulnerabilities[name]
    if (!item || !Array.isArray(item.via) || !item.via.length || path.has(name)) {
      throw new Error(`Incomplete or cyclic audit dependency: ${name}`)
    }
    for (const via of item.via) {
      if (typeof via === 'string') { visit(via, new Set(path).add(name)); continue }
      if (!via || typeof via !== 'object' || !['info', 'low', 'moderate', 'high', 'critical'].includes(via.severity)) throw new Error('Invalid advisory')
      if (!['high', 'critical'].includes(via.severity)) continue
      const devOnly = name === 'braces' && item.nodes?.length > 0 && item.nodes.every((node) =>
        lock.packages[node]?.dev === true && lock.packages[node]?.version === '3.0.3')
      if (devOnly && via.severity === 'high' && via.name === 'braces' && via.url === advisoryUrl && now < expiresAt) continue
      failures.add(via.url || `${name}: unknown advisory`)
    }
  }
  for (const [name, item] of Object.entries(report.vulnerabilities)) {
    if (['high', 'critical'].includes(item.severity)) visit(name)
  }
  return [...failures]
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const audit = spawnSync('npm', ['audit', '--json', '--audit-level=high'], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 })
    if (audit.error || audit.signal || ![0, 1].includes(audit.status)) throw new Error('npm audit failed')
    const lock = JSON.parse(readFileSync(new URL('../package-lock.json', import.meta.url), 'utf8'))
    const failures = auditFailures(JSON.parse(audit.stdout), lock)
    if (failures.length) throw new Error(`npm audit blocked: ${failures.join(', ')}`)
    console.log(`npm audit passed; only dev-only braces ${advisoryUrl} may be excepted until 2026-11-08`)
  } catch (error) { console.error(error.message); process.exitCode = 1 }
}
