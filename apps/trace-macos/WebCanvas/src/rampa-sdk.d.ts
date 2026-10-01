// @basiclines/rampa-sdk 6.0.0 points "types" at dist/index.d.ts but does not publish it.
declare module '@basiclines/rampa-sdk' {
  interface RampaColor {
    readonly hex: string
    readonly oklch: { l: number; c: number; h: number }
    mix(other: string, ratio: number, space: 'oklab'): RampaColor
    set(values: { lightness?: number; chroma?: number; hue?: number }): RampaColor
  }

  export function color(value: string): RampaColor
  export function lint(foreground: string, background: string): { score: number }
}
