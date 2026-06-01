'use client'

import { useChat } from 'ai/react'
import { usePathname } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'

interface AIWidgetProps {
  appName: string
  /** Tailwind bottom offset e.g. "bottom-6" — defaults to "bottom-6" */
  position?: string
}

export function AIWidget({ appName, position = 'bottom-6' }: AIWidgetProps) {
  const [open, setOpen] = useState(false)
  const pathname = usePathname()
  const bottomRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const { messages, input, handleInputChange, handleSubmit, isLoading, error } = useChat({
    api: '/api/ai/chat',
  })

  // Auto-scroll to latest message
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // Focus input when panel opens
  useEffect(() => {
    if (open) inputRef.current?.focus()
  }, [open])

  // Keyboard shortcut: Cmd/Ctrl + Shift + K
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === 'k') {
        e.preventDefault()
        setOpen((v) => !v)
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  const onSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    handleSubmit(e, {
      body: { appName, currentPath: pathname },
    })
  }

  return (
    <div className={`fixed right-6 ${position} z-50 flex flex-col items-end gap-3`}>
      {/* Chat panel */}
      {open && (
        <div className="w-[360px] flex flex-col rounded-2xl border border-gray-200 bg-white shadow-2xl overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-3 bg-gray-50 border-b border-gray-200">
            <div className="flex items-center gap-2">
              <SparkleIcon className="w-4 h-4 text-violet-600" />
              <span className="text-sm font-semibold text-gray-800">Claude</span>
              <span className="text-xs text-gray-400 font-normal">· {appName}</span>
            </div>
            <button
              onClick={() => setOpen(false)}
              className="text-gray-400 hover:text-gray-600 transition-colors"
              aria-label="Close"
            >
              <CloseIcon className="w-4 h-4" />
            </button>
          </div>

          {/* Messages */}
          <div className="flex-1 overflow-y-auto p-4 space-y-4 max-h-[440px] min-h-[200px]">
            {messages.length === 0 && (
              <div className="text-center text-sm text-gray-400 pt-8">
                <SparkleIcon className="w-6 h-6 mx-auto mb-2 text-violet-300" />
                Ask about features, code, or anything in this app.
                <br />
                <span className="text-xs mt-1 block">⌘⇧K to toggle</span>
              </div>
            )}

            {messages.map((m) => (
              <div key={m.id} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                <div
                  className={
                    m.role === 'user'
                      ? 'max-w-[80%] rounded-2xl rounded-tr-sm bg-violet-600 px-4 py-2.5 text-sm text-white'
                      : 'max-w-[90%] rounded-2xl rounded-tl-sm bg-gray-100 px-4 py-2.5 text-sm text-gray-800'
                  }
                >
                  <MessageContent content={m.content} />
                </div>
              </div>
            ))}

            {isLoading && (
              <div className="flex justify-start">
                <div className="rounded-2xl rounded-tl-sm bg-gray-100 px-4 py-2.5">
                  <TypingDots />
                </div>
              </div>
            )}

            {error && (
              <p className="text-xs text-red-500 text-center">
                Something went wrong. Try again.
              </p>
            )}

            <div ref={bottomRef} />
          </div>

          {/* Input */}
          <form onSubmit={onSubmit} className="border-t border-gray-200 p-3 flex gap-2">
            <input
              ref={inputRef}
              value={input}
              onChange={handleInputChange}
              placeholder="Ask Claude…"
              disabled={isLoading}
              className="flex-1 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-violet-400 disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={isLoading || !input.trim()}
              className="flex-shrink-0 rounded-xl bg-violet-600 px-3 py-2 text-white hover:bg-violet-700 disabled:opacity-40 transition-colors"
              aria-label="Send"
            >
              <SendIcon className="w-4 h-4" />
            </button>
          </form>
        </div>
      )}

      {/* Floating toggle button */}
      <button
        onClick={() => setOpen((v) => !v)}
        className={`
          w-12 h-12 rounded-full bg-violet-600 text-white shadow-lg
          hover:bg-violet-700 hover:scale-105 active:scale-95
          transition-all duration-150 flex items-center justify-center
          ${open ? 'rotate-90' : ''}
        `}
        aria-label={open ? 'Close Claude' : 'Open Claude'}
      >
        {open ? <CloseIcon className="w-5 h-5" /> : <SparkleIcon className="w-5 h-5" />}
      </button>
    </div>
  )
}

// ── Sub-components ────────────────────────────────────────────────────────────

function MessageContent({ content }: { content: string }) {
  // Render code blocks, preserve newlines — no markdown library needed
  const parts = content.split(/(```[\s\S]*?```)/g)
  return (
    <>
      {parts.map((part, i) =>
        part.startsWith('```') ? (
          <pre
            key={i}
            className="mt-1 overflow-x-auto rounded bg-black/10 p-2 text-xs font-mono whitespace-pre"
          >
            {part.replace(/^```\w*\n?/, '').replace(/```$/, '')}
          </pre>
        ) : (
          <span key={i} className="whitespace-pre-wrap">
            {part}
          </span>
        )
      )}
    </>
  )
}

function TypingDots() {
  return (
    <span className="flex gap-1 items-center py-0.5">
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce"
          style={{ animationDelay: `${i * 150}ms` }}
        />
      ))}
    </span>
  )
}

// ── Icons (inline SVG — no icon-lib dependency) ───────────────────────────────

function SparkleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2l2.4 7.4H22l-6.2 4.5 2.4 7.4L12 17l-6.2 4.3 2.4-7.4L2 9.4h7.6z" />
    </svg>
  )
}

function CloseIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
    </svg>
  )
}

function SendIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z" />
    </svg>
  )
}
