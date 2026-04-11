CREATE DATABASE IF NOT EXISTS xMixingControl CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE xMixingControl;

CREATE TABLE IF NOT EXISTS local_production_queue (
    id INT AUTO_INCREMENT PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL UNIQUE,
    plan_id VARCHAR(50) DEFAULT NULL,
    sku_code VARCHAR(50) NOT NULL,
    sku_name VARCHAR(150) DEFAULT NULL,
    plant_id INT NOT NULL DEFAULT 1,
    target_total_weight FLOAT DEFAULT 0,
    status ENUM('PENDING', 'RUNNING', 'COMPLETED', 'PAUSED') DEFAULT 'PENDING',
    start_time DATETIME DEFAULT NULL,
    end_time DATETIME DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS local_sku_steps (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sku_code VARCHAR(50) NOT NULL,
    phase_no INT NOT NULL DEFAULT 1,
    phase_id VARCHAR(50) NOT NULL,
    step_id INT NOT NULL,
    require_weight FLOAT DEFAULT 0,
    require_temp FLOAT DEFAULT 0,
    require_agitator_rpm INT DEFAULT 0,
    require_ph FLOAT DEFAULT 0,
    require_brix FLOAT DEFAULT 0,
    require_time_sec INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sku (sku_code)
);

CREATE TABLE IF NOT EXISTS local_step_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    batch_id VARCHAR(50) NOT NULL,
    phase_id VARCHAR(50) NOT NULL,
    step_id INT NOT NULL,
    actual_weight FLOAT DEFAULT 0,
    actual_temp FLOAT DEFAULT 0,
    actual_time_taken INT DEFAULT 0,
    actual_ph FLOAT DEFAULT 0,
    actual_brix FLOAT DEFAULT 0,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (batch_id) REFERENCES local_production_queue(batch_id) ON DELETE CASCADE
);
