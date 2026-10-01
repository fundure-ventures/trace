// rampa-sdk bundles Node-only image decoding (fflate workers, file reads).
// Trace only uses its color math, so those entry points fail loudly here.
const unavailable = (name: string) => () => {
  throw new Error(`${name} is unavailable in the Trace web canvas`)
}

export const createRequire = () => unavailable('require')
export const readFileSync = unavailable('readFileSync')
