const dns = require('dns').promises;
const { exec } = require('child_process');
const { promisify } = require('util');
const { query } = require('../database/connection');
const { logger } = require('../utils/logger');

const execAsync = promisify(exec);

/**
 * Check DNS configuration status
 */
async function dnsStatus(input) {
  const { domain } = input;
  
  try {
    const results = {
      domain,
      mx: [],
      spf: null,
      dkim: [],
      dmarc: null,
      verdict: 'unknown'
    };
    
    // Check MX records
    try {
      const mxRecords = await dns.resolveMx(domain);
      results.mx = mxRecords.map(record => ({
        exchange: record.exchange,
        priority: record.priority
      }));
    } catch (error) {
      logger.warn(`Failed to resolve MX records for ${domain}:`, error.message);
    }
    
    // Check SPF record
    try {
      const txtRecords = await dns.resolveTxt(domain);
      const spfRecord = txtRecords.find(record => 
        record.join('').startsWith('v=spf1')
      );
      if (spfRecord) {
        results.spf = spfRecord.join('');
      }
    } catch (error) {
      logger.warn(`Failed to resolve SPF record for ${domain}:`, error.message);
    }
    
    // Check DKIM records (common selectors)
    const dkimSelectors = ['s1', 'default', 'selector1', 'selector2'];
    for (const selector of dkimSelectors) {
      try {
        const dkimDomain = `${selector}._domainkey.${domain}`;
        const txtRecords = await dns.resolveTxt(dkimDomain);
        const dkimRecord = txtRecords.find(record => 
          record.join('').includes('v=DKIM1')
        );
        if (dkimRecord) {
          results.dkim.push({
            selector,
            txt: dkimRecord.join('')
          });
        }
      } catch (error) {
        // DKIM selector not found - this is normal
      }
    }
    
    // Check DMARC record
    try {
      const dmarcDomain = `_dmarc.${domain}`;
      const txtRecords = await dns.resolveTxt(dmarcDomain);
      const dmarcRecord = txtRecords.find(record => 
        record.join('').startsWith('v=DMARC1')
      );
      if (dmarcRecord) {
        results.dmarc = dmarcRecord.join('');
      }
    } catch (error) {
      logger.warn(`Failed to resolve DMARC record for ${domain}:`, error.message);
    }
    
    // Determine verdict
    let score = 0;
    if (results.mx.length > 0) score += 25;
    if (results.spf) score += 25;
    if (results.dkim.length > 0) score += 25;
    if (results.dmarc) score += 25;
    
    if (score >= 100) results.verdict = 'pass';
    else if (score >= 75) results.verdict = 'warn';
    else results.verdict = 'fail';
    
    logger.info(`DNS status check for ${domain}:`, { score, verdict: results.verdict });
    
    return results;
  } catch (error) {
    logger.error('DNS status check failed:', error);
    throw error;
  }
}

/**
 * Get system health status
 */
async function health(input) {
  try {
    const health = {
      timestamp: new Date().toISOString(),
      smtp: 'unknown',
      imap: 'unknown',
      webmail: 'unknown',
      database: 'unknown',
      queueDepth: 0,
      storageFreeGB: 0,
      activeUsers: 0,
      version: '1.0.0'
    };
    
    // Check database connectivity
    try {
      await query('SELECT 1');
      health.database = 'up';
      
      // Get active users count
      const userCount = await query('SELECT COUNT(*) as count FROM users WHERE status = $1', ['active']);
      health.activeUsers = parseInt(userCount.rows[0].count);
    } catch (error) {
      health.database = 'down';
      logger.error('Database health check failed:', error);
    }
    
    // Check SMTP service (simplified - would normally check Postfix)
    try {
      // This would typically check if Postfix is running and accepting connections
      health.smtp = 'up'; // Placeholder
    } catch (error) {
      health.smtp = 'down';
    }
    
    // Check IMAP service (simplified - would normally check Dovecot)
    try {
      // This would typically check if Dovecot is running and accepting connections
      health.imap = 'up'; // Placeholder
    } catch (error) {
      health.imap = 'down';
    }
    
    // Check webmail service
    try {
      // This would typically make an HTTP request to the webmail service
      health.webmail = 'up'; // Placeholder
    } catch (error) {
      health.webmail = 'down';
    }
    
    // Get queue depth (simplified)
    try {
      // This would typically check Postfix queue
      health.queueDepth = 0; // Placeholder
    } catch (error) {
      logger.warn('Failed to get queue depth:', error);
    }
    
    // Get storage info
    try {
      const { stdout } = await execAsync('df -BG / | tail -1 | awk \'{print $4}\'');
      health.storageFreeGB = parseInt(stdout.replace('G', '')) || 0;
    } catch (error) {
      logger.warn('Failed to get storage info:', error);
    }
    
    logger.info('Health check completed:', health);
    
    return health;
  } catch (error) {
    logger.error('Health check failed:', error);
    throw error;
  }
}

/**
 * Get system metrics for monitoring
 */
async function getMetrics() {
  try {
    const metrics = {
      timestamp: new Date().toISOString(),
      users: {
        total: 0,
        active: 0,
        suspended: 0
      },
      mail: {
        sent_today: 0,
        received_today: 0,
        queue_depth: 0
      },
      storage: {
        used_gb: 0,
        free_gb: 0,
        quota_usage_percent: 0
      },
      performance: {
        avg_response_time_ms: 0,
        error_rate_percent: 0
      }
    };
    
    // Get user statistics
    const userStats = await query(`
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'active') as active,
        COUNT(*) FILTER (WHERE status = 'suspended') as suspended
      FROM users
    `);
    
    if (userStats.rows.length > 0) {
      metrics.users = {
        total: parseInt(userStats.rows[0].total),
        active: parseInt(userStats.rows[0].active),
        suspended: parseInt(userStats.rows[0].suspended)
      };
    }
    
    // Get mail statistics (would be implemented with actual mail logs)
    // For now, return placeholder data
    
    return metrics;
  } catch (error) {
    logger.error('Failed to get metrics:', error);
    throw error;
  }
}

module.exports = {
  dnsStatus,
  health,
  getMetrics
};