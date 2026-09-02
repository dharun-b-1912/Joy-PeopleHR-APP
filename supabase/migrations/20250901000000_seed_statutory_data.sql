-- Seed statutory details for existing employees
-- This migration adds PAN, PF, UAN, ESI numbers and bank account numbers

-- 1. Insert statutory details for employees who don't have them yet
INSERT INTO employee_statutory_details (id, employee_id, pan_number, pf_number, uan_number, esi_number, tax_regime, created_at, updated_at)
SELECT
  'stat-' || e.id,
  e.id,
  CASE
    WHEN e.employee_code = 'JCS-017' THEN 'ABCDE1234F'
    WHEN e.employee_code = 'JCS-024' THEN 'FGHIJ5678K'
    WHEN e.employee_code = 'JCS-031' THEN 'LMNOP9012Q'
    ELSE 'pending'
  END,
  CASE
    WHEN e.employee_code = 'JCS-017' THEN 'MAS00532540000012345'
    WHEN e.employee_code = 'JCS-024' THEN 'MAS00532540000067890'
    WHEN e.employee_code = 'JCS-031' THEN 'MAS00532540000011111'
    ELSE 'pending'
  END,
  CASE
    WHEN e.employee_code = 'JCS-017' THEN '100234567890'
    WHEN e.employee_code = 'JCS-024' THEN '100234567891'
    WHEN e.employee_code = 'JCS-031' THEN '100234567892'
    ELSE 'pending'
  END,
  CASE
    WHEN e.employee_code = 'JCS-017' THEN '23000000001'
    WHEN e.employee_code = 'JCS-024' THEN '23000000002'
    WHEN e.employee_code = 'JCS-031' THEN '23000000003'
    ELSE 'pending'
  END,
  CASE
    WHEN e.employee_code = 'JCS-017' THEN 'NEW'
    WHEN e.employee_code = 'JCS-024' THEN 'OLD'
    WHEN e.employee_code = 'JCS-031' THEN 'NEW'
    ELSE 'NEW'
  END,
  NOW(),
  NOW()
FROM employees e
WHERE NOT EXISTS (
  SELECT 1 FROM employee_statutory_details s WHERE s.employee_id = e.id
);

-- 2. Update bank accounts with actual account numbers (they're currently empty)
UPDATE employee_bank_accounts
SET account_number = CASE
    WHEN employee_id = 'EMP-617871' THEN '50100123456789'
    WHEN employee_id = 'EMP-305036' THEN '50100987654321'
    WHEN employee_id = 'EMP-526715' THEN '50100112233445'
    ELSE account_number
  END,
  branch_name = CASE
    WHEN employee_id = 'EMP-617871' THEN 'Coimbatore Branch'
    WHEN employee_id = 'EMP-305036' THEN 'Chennai Branch'
    WHEN employee_id = 'EMP-526715' THEN 'Coimbatore Branch'
    ELSE branch_name
  END,
  updated_at = NOW()
WHERE account_number IS NULL OR account_number = '';
