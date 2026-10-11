/*
=============================================================
Create Database (MySQL 8.0)
=============================================================
Script Purpose:
    Creates the 'DataWareHouse' database, dropping and recreating it if it
    already exists.

    bronze_*  raw tables loaded from the CRM / ERP CSV files
    silver_*  cleaned and standardised tables (load_silver procedure)
    gold_*    business-ready views (dimensions, facts, reports)
*/

-- Drop and recreate the 'DataWareHouse' database
DROP DATABASE IF EXISTS DataWareHouse;

CREATE DATABASE DataWareHouse
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE DataWareHouse;

-- (Workbench: connection > Advanced > Others > OPT_LOCAL_INFILE=1).
-- SET GLOBAL local_infile = 1;
