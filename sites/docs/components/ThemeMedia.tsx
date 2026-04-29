'use client'

/// <reference lib="dom" />

import { useEffect, useState } from 'react'
import Image from 'next/image'

type Mode = 'light' | 'dark'

declare const document: {
  documentElement: {
    classList: { contains(value: string): boolean }
  }
}

declare const MutationObserver: {
  new (
    callback: () => void
  ): {
    observe(
      target: unknown,
      options: { attributes: boolean; attributeFilter: string[] }
    ): void
    disconnect(): void
  }
}

function getMode(): Mode {
  if (typeof document === 'undefined') return 'light'
  return document.documentElement.classList.contains('dark') ? 'dark' : 'light'
}

function useDocumentMode(): Mode {
  const [mode, setMode] = useState<Mode>('light')

  useEffect(() => {
    const html = document.documentElement
    const update = () => setMode(getMode())
    const observer = new MutationObserver(update)

    update()
    observer.observe(html, { attributes: true, attributeFilter: ['class'] })

    return () => observer.disconnect()
  }, [])

  return mode
}

export function ThemeImage({
  alt,
  className = 'platform-diagram',
  darkSrc,
  height,
  lightSrc,
  priority = false,
  width,
}: {
  alt: string
  className?: string
  darkSrc: string
  height: number
  lightSrc: string
  priority?: boolean
  width: number
}) {
  const mode = useDocumentMode()
  const src = mode === 'dark' ? darkSrc : lightSrc

  return (
    <figure className={className}>
      <Image
        alt={alt}
        className="platform-diagram-image"
        height={height}
        priority={priority}
        src={src}
        width={width}
      />
    </figure>
  )
}
