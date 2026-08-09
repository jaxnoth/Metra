/**
 * Desk-only Markdown renderer for Metra Ask replies.
 * Journal / transport stay raw Markdown text - this is presentation only.
 *
 * Security: treat every engine reply as potentially hostile.
 * - rehype-sanitize allowlist (no raw HTML passthrough)
 * - Links: http(s) only - intentionally deny javascript:, data:, file:, and other schemes
 * - No dangerouslySetInnerHTML
 */
import type { Components } from 'react-markdown'
import ReactMarkdown from 'react-markdown'
import rehypeSanitize, { defaultSchema } from 'rehype-sanitize'
import type { Schema } from 'hast-util-sanitize'

/** Allow only http/https hrefs. Deny javascript:, data:, file:, etc. */
function isSafeHttpUrl(href: string | undefined | null): boolean {
  if (!href || typeof href !== 'string') return false
  const trimmed = href.trim()
  if (!trimmed) return false
  // Protocol-relative URLs - treat as https for allow check
  if (trimmed.startsWith('//')) return true
  // Relative paths / fragments - safe within the desk SPA
  if (trimmed.startsWith('/') || trimmed.startsWith('#') || trimmed.startsWith('?')) return false
  try {
    const u = new URL(trimmed, 'https://example.invalid')
    return u.protocol === 'http:' || u.protocol === 'https:'
  } catch {
    return false
  }
}

const askSanitizeSchema: Schema = {
  ...defaultSchema,
  tagNames: [
    'p',
    'strong',
    'em',
    'ul',
    'ol',
    'li',
    'code',
    'pre',
    'a',
    'h1',
    'h2',
    'h3',
    'h4',
    'blockquote',
    'hr',
    'br',
  ],
  attributes: {
    ...defaultSchema.attributes,
    a: ['href', 'title'],
    code: ['className'],
    pre: [],
  },
  // Intentional design constraint: Metra replies must never create executable or local-file links.
  protocols: {
    ...defaultSchema.protocols,
    href: ['http', 'https'],
  },
}

const components: Components = {
  a({ href, children, title }) {
    if (!isSafeHttpUrl(href)) {
      return <span className="ask-md-link-stripped">{children}</span>
    }
    return (
      <a href={href} title={title} target="_blank" rel="noopener noreferrer">
        {children}
      </a>
    )
  },
  pre({ children }) {
    return <pre className="ask-md-pre">{children}</pre>
  },
  code({ className, children, ...props }) {
    // Fenced blocks get a language-* className from the parser; inline code does not.
    const isFence = Boolean(className)
    if (isFence) {
      return (
        <code className={`ask-md-code-block ${className || ''}`.trim()} {...props}>
          {children}
        </code>
      )
    }
    return (
      <code className="ask-md-code-inline" {...props}>
        {children}
      </code>
    )
  },
}

type AskMarkdownProps = {
  text: string
  className?: string
}

export function AskMarkdown({ text, className }: AskMarkdownProps) {
  const body = text ?? ''
  if (!body.trim()) return null
  return (
    <div className={['ask-md', className].filter(Boolean).join(' ')}>
      <ReactMarkdown rehypePlugins={[[rehypeSanitize, askSanitizeSchema]]} components={components}>
        {body}
      </ReactMarkdown>
    </div>
  )
}
