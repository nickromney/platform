import {test, expect} from 'bun:test'
import {checkNextAdvisories} from '../scripts/check-next-advisories.mjs'

function lock(next = '16.4.1', sharp = '0.35.5', extra = '') {
  return `{"packages":{"next":["next@${next}", "", {"optionalDependencies":{"sharp":">=0.34.0"}}], "sharp":["sharp@${sharp}", "", {}], ${extra}}}`
}

test('accepts patched lockfile including JSONC trailing commas', () => {
  expect(() => checkNextAdvisories(lock())).not.toThrow()
})

test('rejects the previously locked Next.js independently of sharp', () => {
  expect(() => checkNextAdvisories(lock('16.2.6'))).toThrow('Next.js 16.4.1')
})

test('rejects the previously locked sharp independently of Next.js', () => {
  expect(() => checkNextAdvisories(lock('16.4.1', '0.34.5'))).toThrow('sharp 0.35.5')
})

test('checks nested resolution before the root sharp', () => {
  expect(() => checkNextAdvisories(lock('16.4.1', '0.35.5', '"next/sharp":["sharp@0.34.5", "", {}],'))).toThrow('next/sharp')
})

test('ignores an unrelated scoped package named next', () => {
  expect(() => checkNextAdvisories(lock('16.4.1', '0.35.5', '"@example/next":["@example/next@1.0.0", "", {}],'))).not.toThrow()
})

test('does not treat a scope as a package ancestor', () => {
  const extra = '"next/sharp":["sharp@0.35.5", "", {}], "@example/package/next":["next@16.4.1", "", {"optionalDependencies":{"sharp":">=0.34.0"}}], "@example/sharp":["sharp@0.35.5", "", {}],'
  expect(() => checkNextAdvisories(lock('16.4.1', '0.34.5', extra))).toThrow('sharp 0.35.5')
})

test('fails closed on malformed and missing lock entries', () => {
  expect(() => checkNextAdvisories('{')).toThrow()
  expect(() => checkNextAdvisories('{"packages":{"next":["next@16.4.1", "", {}], "sharp":["sharp@0.35.5"]}}')).toThrow('does not declare sharp')
  expect(() => checkNextAdvisories(lock().replace('>=0.34.0', '^0.34.0'))).toThrow('does not satisfy')
  expect(() => checkNextAdvisories(lock().replace(/, "sharp":\["sharp@0.35.5", "", {}\]/, ''))).toThrow('sharp')
  expect(() => checkNextAdvisories('{"packages":{}}')).toThrow('root next')
  expect(() => checkNextAdvisories(lock('16.4.1-canary.1'))).toThrow('invalid next')
})
