/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
*/

use DataWareHouse;

DROP PROCEDURE IF EXISTS load_silver_crm_cust_info;  -- superseded
DROP PROCEDURE IF EXISTS load_silver;
DELIMITER //

CREATE PROCEDURE load_silver()
BEGIN

		-- data trans & cleans crm cust
		insert into silver_crm_cust_info0 (
		cst_id,
		cst_key,
		cst_firstname,
		cst_lastname,
		cst_marital_status,
		cst_gndr,
		cst_create_date)

		select
		cst_id,
		cst_key,
		trim(cst_firstname) as cst_firstname,
		trim(cst_lastname) as cst_lastname,
		case
			when upper(trim(cst_marital_status)) = 'M' then 'Married'
			when upper(trim(cst_marital_status)) = 'F' then 'Single'
			else 'N/A'
		end cst_marital_status,
		case
			when upper(trim(cst_gndr)) = 'M' then 'Male'
			when upper(trim(cst_gndr)) = 'F' then 'Female'
			else 'N/A'
		end cst_gndr,
		cst_create_date
		from (
		select
		*,
		row_number() over (partition by cst_id order by cst_create_date desc) as flag_last
		from bronze_crm_cust_info
		)t where flag_last = 1;


		-- datetime fix
		/* ALTER TABLE silver_crm_cust_info0
			MODIFY dwh_create_date DATETIME DEFAULT CURRENT_TIMESTAMP;

		CALL load_silver();

		SHOW CREATE TABLE silver_crm_cust_info0;   -- should show DEFAULT CURRENT_TIMESTAMP
		SELECT cst_id, dwh_create_date FROM silver_crm_cust_info0 LIMIT 5;

		*/

		/* ----------------------------------------------------------------------------------- */

		-- data trans & cleans crm prd

		insert into silver_crm_prd_info (
			prd_id,
			cat_id,
			prd_key,
			prd_nm,
			prd_cost,
			prd_line,
			prd_start_dt,
			prd_end_dt
		)
		select 
		prd_id,
		replace(substring(prd_key,1,5),'-','_') as cat_id,
		substring(prd_key,7,length(prd_key)) as prd_key,
		trim(prd_nm) as prd_nm,
		COALESCE(NULLIF(TRIM(prd_cost), ''), '0') AS prd_cost,
		case upper(trim(prd_line))
			when 'M' then 'Mountain'
			when 'R' then 'Road'
			when 'S' then 'other Sales'
			when 'T' then 'Touring'
			else 'N/A'
		end prd_line,
		CAST(prd_start_dt AS DATE) AS prd_start_dt,
		DATE_SUB(
			LEAD(CAST(prd_start_dt AS DATE)) OVER (PARTITION BY prd_key ORDER BY CAST(prd_start_dt AS DATE)),
			INTERVAL 1 DAY
		) AS prd_end_dt
		from bronze_crm_prd_info;

		-- where substring(prd_key,7,length(prd_key)) not in (select sls_prd_key from bronze_crm_sales_det);

		-- data trans & cleans crm sales
		insert into silver_crm_sales_det (
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price,
			dwh_create_date
		)
		select
		sls_ord_num,
		sls_prd_key,
		sls_cust_id,
		case when sls_order_dt <=0 or length(sls_order_dt) !=8 then null
			 else cast(sls_order_dt as date)
		end sls_order_dt,
		case when sls_ship_dt <=0 or length(sls_ship_dt) !=8 then null
			 else cast(sls_ship_dt as date)
		end sls_ship_dt,
		case when sls_due_dt <=0 or length(sls_due_dt) !=8 then null
			 else cast(sls_due_dt as date)
		end sls_due_dt,
		case when sls_sales != sls_quantity * sls_price or sls_sales is null or sls_sales <=0
			 then sls_quantity * abs(sls_price)
			 else sls_sales
		end sls_sales,
		sls_quantity,
		case when sls_price is null or sls_price <=0
			 then sls_sales / nullif(sls_quantity, 0)
			 else sls_sales
		end sls_price
		from bronze_crm_sales_det;

	-- data trans & cleans erp cust
		insert into silver_erp_cust_az12 (
		cid,
		bdate,
		gen
		)
		select
		case when cid like 'NAS%' then substring(cid, 4, length(cid))
			 else cid
		end cid,
		case when bdate > curdate() then null
			 else bdate
			 end bdate,
		case when upper(trim(gen)) in ('F', 'FEMALE') THEN 'Female'
			 when upper(trim(gen)) in ('M', 'MALE') THEN 'Male'
			 else 'N/A'
		end gen
		from bronze_erp_cust_az12;

		-- data trans & cleans erp loc
		insert into silver_erp_loc_a101 (
		cid,
		cntry
		)
		select
		replace(cid,'-','') cid,
		case when trim(cntry) = 'DE' then 'Germany'
			 when trim(cntry) in ('US','USA') then 'United States'
			 when trim(cntry) = '' or trim(cntry) is null then 'N/A'
			 else trim(cntry)
		end cntry
		from bronze_erp_loc_a101;

		-- data trans & cleans epr cat

		-- unwanted spaces
		 
		 insert into silver_erp_px_cat_g1v2 (
		 id,
		 cat,
		 subcat,
		 maintenance
		 )
		 select
		 id,
		 cat,
		 subcat,
		 maintenance
		 from bronze_erp_px_cat_g1v2;

END //

DELIMITER ;

CALL load_silver();


-- where sls_cust_id not in (select cst_id from silver_crm_cust_info0); 

-- check for:
-- date null/length/boundary
select
nullif(sls_due_dt,0) sls_due_dt
from silver_crm_sales_det
where sls_due_dt <= 0
or length(sls_due_dt) !=8
or sls_due_dt > 20500101
or sls_due_dt < 19000101;

-- invalid date orders
select *
from silver_crm_sales_det
where sls_order_dt > sls_ship_dt or sls_order_dt > sls_due_dt;

-- numeric quality
select
sls_sales,
sls_quantity,
sls_price
from silver_crm_sales_det
where sls_sales != sls_quantity * sls_price
or sls_sales is null or sls_quantity is null or sls_price is null
or sls_sales <=0 or sls_quantity <=0 or sls_price <=0
order by sls_sales, sls_quantity, sls_price;
