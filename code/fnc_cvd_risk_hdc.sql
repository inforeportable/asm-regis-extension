DELIMITER //

DROP FUNCTION IF EXISTS fnc_cvd_risk_hdc //

CREATE FUNCTION fnc_cvd_risk_hdc(
    p_age INT,          -- AGE: อายุ (ปี)
    p_sex INT,          -- SEX: 1 = ชาย, 0 = หญิง
    p_smoke INT,        -- SMOKING: 1 = สูบ, 0 = ไม่สูบ
    p_dm INT,           -- DM: 1 = เป็นเบาหวาน, 0 = ไม่เป็นเบาหวาน
    p_sbp INT,          -- SBP: ความดันโลหิตตัวบน (mmHg)
    p_chol INT,         -- CHOL: Total Cholesterol (mg/dL) [ใส่ 0 หรือ NULL หากไม่มี]
    p_waist DOUBLE,     -- Waist: รอบเอว (ซม.) [ใส่ 0 หรือ NULL หากไม่มี]
    p_height DOUBLE     -- Height: ส่วนสูง (ซม.) [ใส่ 0 หรือ NULL หากไม่มี]
)
RETURNS VARCHAR(500)
DETERMINISTIC
BEGIN
    -- ตัวแปรสถานะและคำอธิบาย
    DECLARE v_status INT DEFAULT 0;
    DECLARE v_note VARCHAR(255) DEFAULT '';
    
    -- ตัวแปรคำนวณ
    DECLARE v_whr DOUBLE DEFAULT 0;
    DECLARE v_sur_root DOUBLE DEFAULT 0.978296; -- ค่ารอดชีวิตอ้างอิงของ HDC
    
    DECLARE v_full_score DOUBLE DEFAULT 0;
    DECLARE v_predicted_risk DOUBLE DEFAULT 0;
    
    DECLARE v_method VARCHAR(10) DEFAULT 'NONE';
    DECLARE v_risk_level INT DEFAULT 0;
    DECLARE v_risk_group_th VARCHAR(50) DEFAULT '-';
    DECLARE v_risk_group_en VARCHAR(50) DEFAULT '-';

    -- Safe Null Handling
    SET p_smoke = IFNULL(p_smoke, 0);
    SET p_dm = IFNULL(p_dm, 0);
    SET p_chol = IFNULL(p_chol, 0);
    SET p_waist = IFNULL(p_waist, 0);
    SET p_height = IFNULL(p_height, 0);

    -- ==========================================
    -- 1. VALIDATION CHECK (ตรวจสอบข้อมูลนำเข้า)
    -- ==========================================
    IF p_age IS NULL OR p_age <= 0 THEN
        SET v_note = 'ข้อมูลไม่ถูกต้อง: ต้องระบุอายุ (และต้องมากกว่า 0 ปี)';
    ELSEIF p_sex IS NULL OR p_sex NOT IN (0, 1) THEN
        SET v_note = 'ข้อมูลไม่ถูกต้อง: ระบุเพศไม่ถูกต้อง (1 = ชาย, 0 = หญิง)';
    ELSEIF p_sbp IS NULL OR p_sbp < 70 THEN
        SET v_note = 'ข้อมูลไม่ถูกต้อง: ค่า SBP ต้องมากกว่าหรือเท่ากับ 70 mmHg';
    ELSEIF p_chol <= 0 AND (p_waist <= 0 OR p_height <= 0) THEN
        SET v_note = 'ข้อมูลไม่ครบถ้วน: ต้องระบุค่า Total Cholesterol (CHOL) หรือ (รอบเอว และ ส่วนสูง)';
    ELSE
        SET v_status = 1;
    END IF;

    -- ==========================================
    -- 2. CALCULATION (ประมวลผลคำนวณ)
    -- ==========================================
    IF v_status = 1 THEN
        -- กรณีที่ 1: มีค่า Total Cholesterol
        IF p_chol > 0 THEN
            SET v_method = 'TC';
            SET v_full_score = (0.08183 * p_age) + (0.39499 * p_sex) + (0.02084 * p_sbp) + (0.69974 * p_dm) + (0.00212 * p_chol) + (0.41916 * p_smoke);
            SET v_predicted_risk = (1 - POW(v_sur_root, EXP(v_full_score - 7.04423))) * 100;

        -- กรณีที่ 2: ไม่มี TC แต่มีรอบเอวและส่วนสูง (WHR)
        ELSEIF p_waist > 0 AND p_height > 0 THEN
            SET v_method = 'WHR';
            SET v_whr = p_waist / p_height;
            SET v_full_score = (0.079 * p_age) + (0.128 * p_sex) + (0.019350987 * p_sbp) + (0.58454 * p_dm) + (3.512566 * v_whr) + (0.459 * p_smoke);
            SET v_predicted_risk = (1 - POW(v_sur_root, EXP(v_full_score - 7.720484))) * 100;
        END IF;

        -- Prevent Negative Values
        IF v_predicted_risk < 0 THEN
            SET v_predicted_risk = 0;
        END IF;

        -- ==========================================
        -- 3. RISK LEVEL CLASSIFICATION (จัดกลุ่ม 5 ระดับ)
        -- ==========================================
        IF v_predicted_risk < 10 THEN
            SET v_risk_level = 1;
            SET v_risk_group_th = 'ระดับ 1: ความเสี่ยงต่ำ';
            SET v_risk_group_en = 'Level 1: Low Risk';
        ELSEIF v_predicted_risk >= 10 AND v_predicted_risk < 20 THEN
            SET v_risk_level = 2;
            SET v_risk_group_th = 'ระดับ 2: ความเสี่ยงปานกลาง';
            SET v_risk_group_en = 'Level 2: Medium Risk';
        ELSEIF v_predicted_risk >= 20 AND v_predicted_risk < 30 THEN
            SET v_risk_level = 3;
            SET v_risk_group_th = 'ระดับ 3: ความเสี่ยงสูง';
            SET v_risk_group_en = 'Level 3: High Risk';
        ELSEIF v_predicted_risk >= 30 AND v_predicted_risk < 40 THEN
            SET v_risk_level = 4;
            SET v_risk_group_th = 'ระดับ 4: ความเสี่ยงสูงมาก';
            SET v_risk_group_en = 'Level 4: Very High Risk';
        ELSEIF v_predicted_risk >= 40 THEN
            SET v_risk_level = 5;
            SET v_risk_group_th = 'ระดับ 5: ความเสี่ยงสูงอันตราย';
            SET v_risk_group_en = 'Level 5: Critical Risk';
        END IF;

        SET v_note = CONCAT('ประมวลผลสำเร็จ โดยใช้สูตร HDC (', v_method, ')');
    END IF;

    -- ==========================================
    -- 4. RETURN STRING (คั่นด้วย |)
    -- ==========================================
    RETURN CONCAT_WS('|',
        v_status,
        v_method,
        ROUND(v_predicted_risk, 2),
        v_risk_level,
        v_risk_group_th,
        v_risk_group_en,
        v_note
    );

END //

DELIMITER ;
