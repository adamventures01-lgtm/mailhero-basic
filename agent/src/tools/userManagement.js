const bcrypt = require('bcrypt');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../database/connection');
const { logger } = require('../utils/logger');

/**
 * Provision a new user mailbox
 */
async function provisionUser(input) {
  const { email, displayName, password, quotaMB = 5120, aliases = [] } = input;
  
  try {
    // Check if user already exists
    const existingUser = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (existingUser.rows.length > 0) {
      throw new Error('User already exists');
    }
    
    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);
    
    // Create user
    const userResult = await query(
      'INSERT INTO users (email, display_name, password_hash, quota_mb) VALUES ($1, $2, $3, $4) RETURNING id',
      [email, displayName, passwordHash, quotaMB]
    );
    
    const userId = userResult.rows[0].id;
    
    // Create aliases if provided
    const createdAliases = [];
    for (const alias of aliases) {
      await query(
        'INSERT INTO aliases (user_id, alias_email) VALUES ($1, $2)',
        [userId, alias]
      );
      createdAliases.push(alias);
    }
    
    // Create maildir structure (this would typically be done via Postfix/Dovecot)
    // For now, we'll log the action
    logger.info(`Mailbox provisioned for ${email}`, { userId, aliases: createdAliases });
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, 'USER_CREATED', { email, displayName, quotaMB, aliases: createdAliases }]
    );
    
    return {
      status: 'created',
      userId,
      aliases: createdAliases
    };
  } catch (error) {
    logger.error('Failed to provision user:', error);
    throw error;
  }
}

/**
 * Suspend or delete a user
 */
async function suspendUser(input) {
  const { email, mode } = input;
  
  try {
    const userResult = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userId = userResult.rows[0].id;
    
    if (mode === 'suspend') {
      await query('UPDATE users SET status = $1 WHERE id = $2', ['suspended', userId]);
      logger.info(`User suspended: ${email}`);
    } else if (mode === 'delete') {
      // Soft delete - mark as deleted but keep data for audit
      await query('UPDATE users SET status = $1 WHERE id = $2', ['deleted', userId]);
      logger.info(`User deleted: ${email}`);
    }
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, mode === 'suspend' ? 'USER_SUSPENDED' : 'USER_DELETED', { email, mode }]
    );
    
    return { status: 'ok' };
  } catch (error) {
    logger.error(`Failed to ${mode} user:`, error);
    throw error;
  }
}

/**
 * Set user password
 */
async function setPassword(input) {
  const { email, newPassword, forceLogout = true } = input;
  
  try {
    const userResult = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userId = userResult.rows[0].id;
    const passwordHash = await bcrypt.hash(newPassword, 10);
    
    await query('UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', 
                [passwordHash, userId]);
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, 'PASSWORD_CHANGED', { email, forceLogout }]
    );
    
    logger.info(`Password updated for user: ${email}`);
    
    return { status: 'ok' };
  } catch (error) {
    logger.error('Failed to set password:', error);
    throw error;
  }
}

/**
 * Create email alias
 */
async function createAlias(input) {
  const { email, alias } = input;
  
  try {
    const userResult = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userId = userResult.rows[0].id;
    
    // Check if alias already exists
    const existingAlias = await query('SELECT id FROM aliases WHERE alias_email = $1', [alias]);
    if (existingAlias.rows.length > 0) {
      throw new Error('Alias already exists');
    }
    
    await query('INSERT INTO aliases (user_id, alias_email) VALUES ($1, $2)', [userId, alias]);
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, 'ALIAS_CREATED', { email, alias }]
    );
    
    logger.info(`Alias created: ${alias} -> ${email}`);
    
    return { status: 'ok' };
  } catch (error) {
    logger.error('Failed to create alias:', error);
    throw error;
  }
}

/**
 * Remove email alias
 */
async function removeAlias(input) {
  const { email, alias } = input;
  
  try {
    const userResult = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userId = userResult.rows[0].id;
    
    const result = await query('DELETE FROM aliases WHERE user_id = $1 AND alias_email = $2', 
                              [userId, alias]);
    
    if (result.rowCount === 0) {
      throw new Error('Alias not found');
    }
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, 'ALIAS_REMOVED', { email, alias }]
    );
    
    logger.info(`Alias removed: ${alias}`);
    
    return { status: 'ok' };
  } catch (error) {
    logger.error('Failed to remove alias:', error);
    throw error;
  }
}

/**
 * Set email forwarding
 */
async function setForwarding(input) {
  const { email, forwardTo, keepCopy = true } = input;
  
  try {
    const userResult = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userId = userResult.rows[0].id;
    
    // Remove existing forwarding rules
    await query('DELETE FROM forwarding WHERE user_id = $1', [userId]);
    
    // Add new forwarding rule
    await query('INSERT INTO forwarding (user_id, forward_to, keep_copy) VALUES ($1, $2, $3)',
                [userId, forwardTo, keepCopy]);
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, 'FORWARDING_SET', { email, forwardTo, keepCopy }]
    );
    
    logger.info(`Forwarding set for ${email}:`, { forwardTo, keepCopy });
    
    return { status: 'ok' };
  } catch (error) {
    logger.error('Failed to set forwarding:', error);
    throw error;
  }
}

/**
 * Set user quota
 */
async function setQuota(input) {
  const { email, quotaMB } = input;
  
  try {
    const userResult = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userId = userResult.rows[0].id;
    
    await query('UPDATE users SET quota_mb = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
                [quotaMB, userId]);
    
    // Log audit event
    await query(
      'INSERT INTO audit_log (user_id, action, details) VALUES ($1, $2, $3)',
      [userId, 'QUOTA_CHANGED', { email, quotaMB }]
    );
    
    logger.info(`Quota set for ${email}: ${quotaMB}MB`);
    
    return { status: 'ok' };
  } catch (error) {
    logger.error('Failed to set quota:', error);
    throw error;
  }
}

module.exports = {
  provisionUser,
  suspendUser,
  setPassword,
  createAlias,
  removeAlias,
  setForwarding,
  setQuota
};