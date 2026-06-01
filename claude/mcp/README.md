# MCP Servers

Model Context Protocol (MCP) servers extend Claude with additional tools and resources. Configure them in `.mcp.json` at the project root (committed to git, shared with team) or in `~/.claude/settings.json` (user-scoped).

## `.mcp.json` template

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}"
      }
    },
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "${DATABASE_URL}"]
    },
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/allowed/path"]
    }
  }
}
```

## Useful MCP servers

| Server | Package | What it adds |
|---|---|---|
| GitHub | `@modelcontextprotocol/server-github` | PR, issue, and repo tools |
| PostgreSQL | `@modelcontextprotocol/server-postgres` | Query and introspect a Postgres DB |
| Filesystem | `@modelcontextprotocol/server-filesystem` | Scoped file access |
| Fetch | `@modelcontextprotocol/server-fetch` | Fetch URLs as tools |
| Linear | via Linear MCP | Create/update Linear issues |
| Slack | via Slack MCP | Read/post Slack messages |

## User-scoped MCP config (`~/.claude/settings.json`)

```json
{
  "mcpServers": {
    "my-private-server": {
      "type": "stdio",
      "command": "node",
      "args": ["/path/to/server/index.js"],
      "env": {
        "API_KEY": "secret"
      }
    }
  }
}
```
