import test from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { parse, babelParse } from 'vue/compiler-sfc'

const frontend = fileURLToPath(new URL('../', import.meta.url))
const rootReads = new Set(['getElementById', 'querySelector', 'querySelectorAll', 'activeElement', 'fullscreenElement'])

function walk(node, visit) {
  if (!node || typeof node !== 'object') return
  if (Array.isArray(node)) { for (const child of node) walk(child, visit); return }
  visit(node)
  for (const child of Object.values(node)) walk(child, visit)
}

function property(node) {
  return node?.computed ? node.property?.value : node?.property?.name
}

function violations(source) {
  const { descriptor } = parse(source)
  const failures = []
  for (const script of [descriptor.script, descriptor.scriptSetup].filter(Boolean)) {
    const ast = babelParse(script.content, { sourceType: 'module', plugins: ['typescript'] })
    const functions = new Map()
    walk(ast, node => {
      if (node.type === 'FunctionDeclaration') functions.set(node.id?.name, node)
      if (node.type === 'VariableDeclarator' && /FunctionExpression$/.test(node.init?.type || '')) functions.set(node.id?.name, node.init)
    })
    walk(ast, node => {
      if (!['MemberExpression', 'OptionalMemberExpression'].includes(node.type) || node.object?.name !== 'document') return
      if (rootReads.has(property(node))) failures.push(`Use the component DOM root instead of document.${property(node)}`)
      if (property(node) !== 'addEventListener') return
    })
    walk(ast, node => {
      if (node.type !== 'CallExpression' || node.callee?.object?.name !== 'document' || property(node.callee) !== 'addEventListener') return
      if (!['pointerdown', 'mousedown', 'click', 'touchstart'].includes(node.arguments[0]?.value)) return
      const callback = node.arguments[1]?.type === 'Identifier' ? functions.get(node.arguments[1].name) : node.arguments[1]
      let contains = false, composed = false
      walk(callback, child => {
        if (child.type !== 'CallExpression') return
        if (property(child.callee) === 'contains') contains = true
        if (property(child.callee) === 'composedPath') composed = true
      })
      if (contains && !composed) failures.push('Document outside-click handlers must account for event.composedPath()')
    })
  }
  walk(descriptor.template?.ast, node => {
    if (node.type !== 1 || node.tag?.toLowerCase() !== 'teleport') return
    if (!node.props.some(prop => prop.type === 6 && prop.name === 'to' && prop.value?.content === 'body')) return
    const disabled = node.props.find(prop => prop.type === 6 && prop.name === 'disabled')
      || node.props.find(prop => prop.type === 7 && prop.name === 'bind' && prop.arg?.content === 'disabled')
    const expression = disabled?.exp?.content?.replace(/\s/g, '')
    if (!disabled || (disabled.type === 7 && !['true', 'runtime.host', 'Boolean(runtime.host)'].includes(expression))) {
      failures.push('Teleport to body must stay inside the module when embedded')
    }
  })
  return failures
}

function vueFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name)
    return entry.isDirectory() ? vueFiles(path) : entry.name.endsWith('.vue') ? [path] : []
  })
}

test('guard detects the known Shadow DOM boundary regressions', () => {
  assert.equal(violations('<script setup>document.getElementById("answer"); document.activeElement; document.fullscreenElement</script>').length, 3)
  assert.equal(violations('<script setup>function outside(event) { panel.contains(event.target) } document.addEventListener("pointerdown", outside)</script>').length, 1)
  assert.equal(violations('<template><Teleport to="body"><div /></Teleport></template>').length, 1)
  assert.equal(violations('<template><Teleport to="body" :disabled="Boolean(runtime.host)"><div /></Teleport></template>').length, 0)
  assert.equal(violations('<script setup>// document.getElementById is deliberately mentioned in a comment\nconst label = "document.activeElement"</script>').length, 0)
})

test('embedded Vue components respect their own DOM root', { skip: !existsSync(join(frontend, 'runtime/entry.js')) }, () => {
  const failures = vueFiles(join(frontend, 'src')).flatMap(path => violations(readFileSync(path, 'utf8')).map(message => `${path.slice(frontend.length)}: ${message}`))
  assert.deepEqual(failures, [])
})
