/*
===============================================================================
Quality Checks
===============================================================================
Script Purpose:
    This script performs various quality checks for data consistency, accuracy, 
    and standardization across the 'silver' layer. It includes checks for:
    - Null or duplicate primary keys.
    - Unwanted spaces in string fields.
    - Data standardization and consistency.
    - Data consistency between related fields.

Usage Notes:
    - Run these checks after data loading Silver Layer.
    - Investigate and resolve any discrepancies found during the checks.
===============================================================================
*/

-- removing unwanted text

-- select * from `silver_crm_cust_info0` to see where join should occur
-- removing unwanted text (substr)
-- identify out of range dates
select distinct bdate from silver_erp_cust_az12;

-- data standardization & consistency
select distinct gen
from silver_erp_cust_az12;

select * from silver_erp_px_cat_g1v2;
-- where replace(cid,'-','') not in (select cst_key from silver_crm_cust_info0); to check if it worked

-- data standardization & consistency
select distinct cntry
from silver_erp_loc_a101
order by cntry;
 
 -- data standardization & consistency
select distinct cat
from silver_erp_px_cat_g1v2;
