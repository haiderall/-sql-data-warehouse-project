/*
===============================================================================
DDL Script: Create Silver Tables
===============================================================================
Script Purpose:
    This script creates tables in the 'silver' schema, dropping existing tables 
    if they already exist.
	Run this script to re-define the DDL structure of 'bronze' Tables
===============================================================================
*/

DROP TABLE IF EXISTS silver_crm_cust_info;
CREATE TABLE silver_crm_cust_info (
    cst_id VARCHAR(50),
    cst_key VARCHAR(50),
    cst_firstname VARCHAR(50),
    cst_lastname VARCHAR(50),
    cst_marital_status VARCHAR(50),
    cst_gndr VARCHAR(50),
    cst_create_date VARCHAR(50),
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_crm_prd_info;
CREATE TABLE silver_crm_prd_info (
    prd_id          INT,
    cat_id          VARCHAR(50),
    prd_key         VARCHAR(50),
    prd_nm          VARCHAR(100),
    prd_cost        DECIMAL(18,2),
    prd_line        VARCHAR(50),
    prd_start_dt    DATE,
    prd_end_dt      DATE,
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_crm_sales_det;
CREATE TABLE silver_crm_sales_det (
    sls_ord_num     VARCHAR(50),
    sls_prd_key     VARCHAR(50),
    sls_cust_id     VARCHAR(50),
    sls_order_dt    DATE,
    sls_ship_dt     DATE,
    sls_due_dt      DATE,
    sls_sales       DECIMAL(18,2),
    sls_quantity    INT,
    sls_price       DECIMAL(18,2),
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_erp_cust_az12;
CREATE TABLE silver_erp_cust_az12 (
    cid             VARCHAR(50),
    bdate           DATE,
    gen             VARCHAR(50),
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_erp_loc_a101;
CREATE TABLE silver_erp_loc_a101 (
    cid             VARCHAR(50),
    cntry           VARCHAR(50),
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS silver_erp_px_cat_g1v2;
CREATE TABLE silver_erp_px_cat_g1v2 (
    id              VARCHAR(50),
    cat             VARCHAR(50),
    subcat          VARCHAR(50),
    maintenance     VARCHAR(50),
    dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ========== SINGLE PROCEDURE ==========
DROP PROCEDURE IF EXISTS load_silver_crm_cust_info;  -- superseded
DROP PROCEDURE IF EXISTS load_silver;
DROP PROCEDURE IF EXISTS load_bronze;

DELIMITER //

CREATE PROCEDURE load_bronze()
BEGIN
    DECLARE current_step VARCHAR(100) DEFAULT 'init';
    DECLARE rows_loaded  INT DEFAULT 0;
    DECLARE batch_start  DATETIME DEFAULT NOW();
    DECLARE error_code   INT DEFAULT 0;
    DECLARE sql_state    VARCHAR(5);
    DECLARE error_msg    TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            error_code = MYSQL_ERRNO,
            sql_state  = RETURNED_SQLSTATE,
            error_msg  = MESSAGE_TEXT;

        SELECT CONCAT('FAILED at [', current_step, '] | Error ', error_code,
                      ' (SQLSTATE ', sql_state, '): ', error_msg) AS ErrorMessage;
    END;

    SELECT '=== Loading Silver Layer ===' AS ' ';

    -- 1. CRM customers ------------------------------------------------
    SET current_step = 'silver_crm_cust_info0';
    TRUNCATE TABLE silver_crm_cust_info0;
    INSERT INTO silver_crm_cust_info0 (
        cst_id, cst_key, cst_firstname, cst_lastname,
        cst_marital_status, cst_gndr, cst_create_date
    )
    WITH ranked_customers AS (
        SELECT
            cst_id,
            TRIM(cst_key) AS cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname) AS cst_lastname,
            CASE WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
                 WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
                 ELSE 'N/A' END AS cst_marital_status,
            CASE WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                 WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                 ELSE 'N/A' END AS cst_gndr,
            cst_create_date,
            ROW_NUMBER() OVER (PARTITION BY cst_id
                               ORDER BY cst_create_date DESC, cst_key DESC) AS flag_last
        FROM bronze_crm_cust_info
        WHERE cst_id IS NOT NULL
    )
    SELECT cst_id, cst_key, cst_firstname, cst_lastname,
           cst_marital_status, cst_gndr, cst_create_date
    FROM ranked_customers
    WHERE flag_last = 1;
    SET rows_loaded = ROW_COUNT();
    SELECT CONCAT('>> ', current_step, ': ', rows_loaded, ' rows') AS ' ';

    -- 2. CRM products -------------------------------------------------
    SET current_step = 'silver_crm_prd_info';
    TRUNCATE TABLE silver_crm_prd_info;
    INSERT INTO silver_crm_prd_info (
        prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt
    )
    SELECT
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        -- end date = next version's start date minus 1 day
        DATE_SUB(LEAD(prd_start_dt) OVER (PARTITION BY cat_id, prd_key
                                          ORDER BY prd_start_dt), INTERVAL 1 DAY) AS prd_end_dt
    FROM (
        SELECT
            prd_id,
            REPLACE(SUBSTRING(TRIM(prd_key), 1, 5), '-', '_') AS cat_id,
            SUBSTRING(TRIM(prd_key), 7) AS prd_key,
            TRIM(prd_nm) AS prd_nm,
            COALESCE(CAST(NULLIF(TRIM(prd_cost), '') AS DECIMAL(18,2)), 0) AS prd_cost,
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'N/A' END AS prd_line,
            STR_TO_DATE(NULLIF(TRIM(prd_start_dt), ''), '%Y-%m-%d') AS prd_start_dt
        FROM bronze_crm_prd_info
    ) p;
    SET rows_loaded = ROW_COUNT();
    SELECT CONCAT('>> ', current_step, ': ', rows_loaded, ' rows') AS ' ';

    -- 3. CRM sales ----------------------------------------------------
    SET current_step = 'silver_crm_sales_det';
    TRUNCATE TABLE silver_crm_sales_det;
    INSERT INTO silver_crm_sales_det (
        sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, sls_ship_dt,
        sls_due_dt, sls_sales, sls_quantity, sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE WHEN sls_order_dt = 0 OR LENGTH(sls_order_dt) <> 8 THEN NULL
             ELSE STR_TO_DATE(CAST(sls_order_dt AS CHAR), '%Y%m%d') END,
        CASE WHEN sls_ship_dt = 0 OR LENGTH(sls_ship_dt) <> 8 THEN NULL
             ELSE STR_TO_DATE(CAST(sls_ship_dt AS CHAR), '%Y%m%d') END,
        CASE WHEN sls_due_dt = 0 OR LENGTH(sls_due_dt) <> 8 THEN NULL
             ELSE STR_TO_DATE(CAST(sls_due_dt AS CHAR), '%Y%m%d') END,
        -- recompute sales if missing / non-positive / inconsistent with qty * price
        CASE WHEN sls_sales IS NULL OR sls_sales <= 0
                  OR sls_sales <> sls_quantity * ABS(sls_price)
             THEN sls_quantity * ABS(sls_price)
             ELSE sls_sales END,
        sls_quantity,
        -- derive price if missing / non-positive
        CASE WHEN sls_price IS NULL OR sls_price <= 0
             THEN sls_sales / NULLIF(sls_quantity, 0)
             ELSE sls_price END
    FROM (
        SELECT
            TRIM(sls_ord_num) AS sls_ord_num,
            TRIM(sls_prd_key) AS sls_prd_key,
            sls_order_dt, sls_ship_dt, sls_due_dt,
            CAST(NULLIF(TRIM(sls_cust_id), '')  AS DECIMAL(18,2)) AS sls_cust_id, 
            CAST(NULLIF(TRIM(sls_sales), '')    AS DECIMAL(18,2)) AS sls_sales,
            CAST(NULLIF(TRIM(sls_quantity), '') AS SIGNED)        AS sls_quantity,
            CAST(NULLIF(TRIM(sls_price), '')    AS DECIMAL(18,2)) AS sls_price
        FROM bronze_crm_sales_det
    ) s;
    SET rows_loaded = ROW_COUNT();
    SELECT CONCAT('>> ', current_step, ': ', rows_loaded, ' rows') AS ' ';

    -- 4. ERP customers ------------------------------------------------
    SET current_step = 'silver_erp_cust_az12';
    TRUNCATE TABLE silver_erp_cust_az12;
    INSERT INTO silver_erp_cust_az12 (cid, bdate, gen)
    SELECT
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4) ELSE cid END,
        CASE WHEN bdate > CURDATE() THEN NULL ELSE bdate END,   -- future birthdates -> NULL
        CASE WHEN UPPER(gen) IN ('F', 'FEMALE') THEN 'Female'
             WHEN UPPER(gen) IN ('M', 'MALE')   THEN 'Male'
             ELSE 'N/A' END
    FROM (
        SELECT TRIM(cid) AS cid,
               STR_TO_DATE(NULLIF(TRIM(bdate), ''), '%Y-%m-%d') AS bdate,
               TRIM(gen) AS gen
        FROM bronze_erp_cust_az12
    ) c;
    SET rows_loaded = ROW_COUNT();
    SELECT CONCAT('>> ', current_step, ': ', rows_loaded, ' rows') AS ' ';

    -- 5. ERP locations ------------------------------------------------
    SET current_step = 'silver_erp_loc_a101';
    TRUNCATE TABLE silver_erp_loc_a101;
    INSERT INTO silver_erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(TRIM(cid), '-', ''),
        CASE WHEN UPPER(TRIM(cntry)) = 'DE' THEN 'Germany'
             WHEN UPPER(TRIM(cntry)) IN ('US', 'USA') THEN 'United States'
             WHEN TRIM(cntry) IS NULL OR TRIM(cntry) = '' THEN 'N/A'
             ELSE TRIM(cntry) END
    FROM bronze_erp_loc_a101;
    SET rows_loaded = ROW_COUNT();
    SELECT CONCAT('>> ', current_step, ': ', rows_loaded, ' rows') AS ' ';

    -- 6. ERP product categories ---------------------------------------
    SET current_step = 'silver_erp_px_cat_g1v2';
    TRUNCATE TABLE silver_erp_px_cat_g1v2;
    INSERT INTO silver_erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT TRIM(id), TRIM(cat), TRIM(subcat), TRIM(maintenance)
    FROM bronze_erp_px_cat_g1v2;
    SET rows_loaded = ROW_COUNT();
    SELECT CONCAT('>> ', current_step, ': ', rows_loaded, ' rows') AS ' ';

    SELECT CONCAT('=== Silver load complete in ',
                  TIMESTAMPDIFF(SECOND, batch_start, NOW()), 's ===') AS ' ';
END //

DELIMITER ;

CALL load_bronze();
