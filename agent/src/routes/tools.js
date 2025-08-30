const express = require('express');
const router = express.Router();
const { validateTool } = require('../middleware/validation');
const { logger } = require('../utils/logger');

// Import tool handlers
const userTools = require('../tools/userManagement');
const mailTools = require('../tools/mailOperations');
const adminTools = require('../tools/adminOperations');

// Tool definitions with schemas
const tools = {
  provisionUser: {
    name: 'provisionUser',
    description: 'Create a new mailbox for a user',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        displayName: { type: 'string' },
        password: { type: 'string', minLength: 8 },
        quotaMB: { type: 'number', default: 5120 },
        aliases: { type: 'array', items: { type: 'string', format: 'email' } }
      },
      required: ['email', 'displayName', 'password']
    },
    handler: userTools.provisionUser
  },
  
  suspendUser: {
    name: 'suspendUser',
    description: 'Suspend or delete a user mailbox',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        mode: { type: 'string', enum: ['suspend', 'delete'] }
      },
      required: ['email', 'mode']
    },
    handler: userTools.suspendUser
  },
  
  setPassword: {
    name: 'setPassword',
    description: 'Change or reset user password',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        newPassword: { type: 'string', minLength: 8 },
        forceLogout: { type: 'boolean', default: true }
      },
      required: ['email', 'newPassword']
    },
    handler: userTools.setPassword
  },
  
  createAlias: {
    name: 'createAlias',
    description: 'Create email alias',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        alias: { type: 'string', format: 'email' }
      },
      required: ['email', 'alias']
    },
    handler: userTools.createAlias
  },
  
  removeAlias: {
    name: 'removeAlias',
    description: 'Remove email alias',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        alias: { type: 'string', format: 'email' }
      },
      required: ['email', 'alias']
    },
    handler: userTools.removeAlias
  },
  
  setForwarding: {
    name: 'setForwarding',
    description: 'Set email forwarding rules',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        forwardTo: { type: 'array', items: { type: 'string', format: 'email' } },
        keepCopy: { type: 'boolean', default: true }
      },
      required: ['email', 'forwardTo']
    },
    handler: userTools.setForwarding
  },
  
  setQuota: {
    name: 'setQuota',
    description: 'Set user mailbox quota',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        quotaMB: { type: 'number', minimum: 100 }
      },
      required: ['email', 'quotaMB']
    },
    handler: userTools.setQuota
  },
  
  sendMail: {
    name: 'sendMail',
    description: 'Send email via SMTP',
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', format: 'email' },
        to: { type: 'array', items: { type: 'string', format: 'email' } },
        cc: { type: 'array', items: { type: 'string', format: 'email' } },
        bcc: { type: 'array', items: { type: 'string', format: 'email' } },
        subject: { type: 'string' },
        html: { type: 'string' },
        text: { type: 'string' },
        attachments: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              name: { type: 'string' },
              base64: { type: 'string' }
            }
          }
        }
      },
      required: ['from', 'to', 'subject']
    },
    handler: mailTools.sendMail
  },
  
  fetchMail: {
    name: 'fetchMail',
    description: 'Fetch emails from mailbox',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        folder: { type: 'string', default: 'INBOX' },
        query: { type: 'string' },
        limit: { type: 'number', default: 50, maximum: 100 },
        cursor: { type: 'string' }
      },
      required: ['email']
    },
    handler: mailTools.fetchMail
  },
  
  setFilter: {
    name: 'setFilter',
    description: 'Set server-side email filters',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        rules: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              if: { type: 'string' },
              then: { type: 'string' }
            }
          }
        }
      },
      required: ['email', 'rules']
    },
    handler: mailTools.setFilter
  },
  
  setAutoreply: {
    name: 'setAutoreply',
    description: 'Set vacation auto-reply',
    inputSchema: {
      type: 'object',
      properties: {
        email: { type: 'string', format: 'email' },
        enabled: { type: 'boolean' },
        subject: { type: 'string' },
        message: { type: 'string' },
        startISO: { type: 'string', format: 'date-time' },
        endISO: { type: 'string', format: 'date-time' }
      },
      required: ['email', 'enabled']
    },
    handler: mailTools.setAutoreply
  },
  
  dnsStatus: {
    name: 'dnsStatus',
    description: 'Check DNS configuration status',
    inputSchema: {
      type: 'object',
      properties: {
        domain: { type: 'string', default: 'mailhero.in' }
      },
      required: ['domain']
    },
    handler: adminTools.dnsStatus
  },
  
  health: {
    name: 'health',
    description: 'Get system health status',
    inputSchema: {
      type: 'object',
      properties: {}
    },
    handler: adminTools.health
  }
};

// GET /tools - List all available tools
router.get('/', (req, res) => {
  const toolList = Object.values(tools).map(tool => ({
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema
  }));
  
  res.json({
    tools: toolList,
    count: toolList.length
  });
});

// POST /tools/:toolName - Execute a specific tool
router.post('/:toolName', validateTool, async (req, res) => {
  const { toolName } = req.params;
  const tool = tools[toolName];
  
  if (!tool) {
    return res.status(404).json({ error: `Tool '${toolName}' not found` });
  }
  
  try {
    logger.info(`Executing tool: ${toolName}`, { input: req.body });
    const result = await tool.handler(req.body);
    logger.info(`Tool executed successfully: ${toolName}`, { result });
    res.json(result);
  } catch (error) {
    logger.error(`Tool execution failed: ${toolName}`, { error: error.message });
    res.status(500).json({ 
      error: 'Tool execution failed',
      message: error.message 
    });
  }
});

module.exports = router;