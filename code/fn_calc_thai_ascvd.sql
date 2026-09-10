DELIMITER //

DROP FUNCTION IF EXISTS fn_calc_thai_ascvd //

CREATE FUNCTION fn_calc_thai_ascvd(
    p_age INT,          -- อายุ (ปี)
    p_sex INT,          -- 0 = หญิง, 1 = ชาย
    p_smoke INT,        -- 0 = ไม่สูบ, 1 = สูบ
    p_dm INT,           -- 0 = ไม่เป็นเบาหวาน, 1 = เป็นเบาหวาน
    p_sbp INT,          -- ความดันโลหิตตัวบน (mmHg)
    p_tc INT,           -- Total Cholesterol (mg/dL) [ใส่ 0 หรือ NULL หากไม่มี]
    p_wc_cm DOUBLE,     -- รอบเอว (ซม.) [ใส่ 0 หรือ NULL หากไม่มี]
    p_height_cm DOUBLE  -- ส่วนสูง (ซม.) [ใส่ 0 หรือ NULL หากไม่มี]
)
RETURNS VARCHAR(500)
DETERMINISTIC
BEGIN
    -- ตัวแปรสถานะ (1 = สำเร็จ, 0 = ข้อผิดพลาด) และคำอธิบาย
    DECLARE v_status INT DEFAULT 0;
    DECLARE v_note VARCHAR(255) DEFAULT '';
    
    -- ตัวแปรคำนวณ
    DECLARE v_whr DOUBLE DEFAULT 0;
    DECLARE v_sur_root DOUBLE DEFAULT 0.964588;
    
    DECLARE v_compare_sbp DOUBLE DEFAULT 120;
    DECLARE v_compare_wc DOUBLE DEFAULT 79;
    DECLARE v_compare_whr DOUBLE DEFAULT 0.52667;
    
    DECLARE v_full_score DOUBLE DEFAULT 0;
    DECLARE v_compare_score DOUBLE DEFAULT 0;
    DECLARE v_predicted_risk DOUBLE DEFAULT 0;
    DECLARE v_compare_risk DOUBLE DEFAULT 0;
    DECLARE v_risk_ratio DOUBLE DEFAULT 0;
    
    DECLARE v_method VARCHAR(10) DEFAULT 'NONE';
    DECLARE v_risk_group_th VARCHAR(50) DEFAULT '-';
    DECLARE v_risk_group_en VARCHAR(50) DEFAULT '-';

    -- Safe Null Handling
    SET p_smoke = IFNULL(p_smoke, 0);
    SET p_dm = IFNULL(p_dm, 0);
    SET p_tc = IFNULL(p_tc, 0);
    SET p_wc_cm = IFNULL(p_wc_cm, 0);
    SET p_height_cm = IFNULL(p_height_cm, 0);

    -- ==========================================
    -- 1. VALIDATION CHECK (ตรวจสอบความถูกต้องของข้อมูล)
    -- ==========================================
    IF p_age IS NULL OR p_age <= 0 THEN
        SET v_note = 'ข้อมูลไม่ถูกต้อง: ต้องระบุอายุ (และต้องมากกว่า 0 ปี)';
    ELSEIF p_sex IS NULL OR p_sex NOT IN (0, 1) THEN
        SET v_note = 'ข้อมูลไม่ถูกต้อง: ระบุเพศไม่ถูกต้อง (0 = หญิง, 1 = ชาย)';
    ELSEIF p_sbp IS NULL OR p_sbp < 70 THEN
        SET v_note = 'ข้อมูลไม่ถูกต้อง: ค่า SBP ต้องมากกว่าหรือเท่ากับ 70 mmHg';
    ELSEIF p_tc <= 0 AND p_wc_cm <= 0 THEN
        SET v_note = 'ข้อมูลไม่ครบถ้วน: ต้องระบุค่า Total Cholesterol (TC) หรือ รอบเอว (WC) อย่างน้อย 1 ค่า';
    ELSE
        -- ข้อมูลครบถ้วน ถูกต้องตามเงื่อนไข (กำหนด status = 1)
        SET v_status = 1;
    END IF;

    -- ==========================================
    -- 2. CALCULATION (ประมวลผลคำนวณเมื่อ status = 1)
    -- ==========================================
    IF v_status = 1 THEN
        -- คำนวณ WHR หากมีข้อมูลรอบเอวและส่วนสูง
        IF p_wc_cm > 0 AND p_height_cm > 0 THEN
            SET v_whr = p_wc_cm / p_height_cm;
        END IF;

        -- กำหนดค่ามาตรฐานเปรียบเทียบ ตามเพศและอายุ
        IF p_sex = 1 THEN
            SET v_compare_whr = 0.58125;
            SET v_compare_wc = 93;
            IF p_age > 60 THEN
                SET v_compare_sbp = 132;
            ELSE
                SET v_compare_sbp = 120;
            END IF;
        ELSE
            SET v_compare_whr = 0.52667;
            SET v_compare_wc = 79;
            IF p_age > 60 THEN
                SET v_compare_sbp = 130;
            ELSE
                SET v_compare_sbp = 115;
            END IF;
        END IF;

        -- เลือกลำดับสูตรคำนวณ (1. TC -> 2. WHR -> 3. WC)
        IF p_tc > 0 THEN
            -- สูตรที่ 1: ใช้ Total Cholesterol (TC)
            SET v_method = 'TC';
            SET v_full_score = (0.08183 * p_age) + (0.39499 * p_sex) + (0.02084 * p_sbp) + (0.69974 * p_dm) + (0.00212 * p_tc) + (0.41916 * p_smoke);
            SET v_compare_score = (0.08183 * p_age) + (0.39499 * p_sex) + (0.02084 * v_compare_sbp) + (0.00212 * 200);
            
            SET v_predicted_risk = 1 - POW(v_sur_root, EXP(v_full_score - 7.04423));
            SET v_compare_risk = 1 - POW(v_sur_root, EXP(v_compare_score - 7.04423));

        ELSEIF v_whr > 0 THEN
            -- สูตรที่ 2: ใช้ อัตราส่วนรอบเอวต่อส่วนสูง (WHR)
            SET v_method = 'WHR';
            SET v_full_score = (0.079 * p_age) + (0.128 * p_sex) + (0.019350987 * p_sbp) + (0.58454 * p_dm) + (3.512566 * v_whr) + (0.459 * p_smoke);
            SET v_compare_score = (0.079 * p_age) + (0.128 * p_sex) + (0.019350987 * v_compare_sbp) + (3.512566 * v_compare_whr);
            
            SET v_predicted_risk = 1 - POW(v_sur_root, EXP(v_full_score - 7.712325));
            SET v_compare_risk = 1 - POW(v_sur_root, EXP(v_compare_score - 7.712325));

        ELSEIF p_wc_cm > 0 THEN
            -- สูตรที่ 3: ใช้ รอบเอว (WC)
            SET v_method = 'WC';
            SET v_full_score = (0.08372 * p_age) + (0.05988 * p_sex) + (0.02034 * p_sbp) + (0.59953 * p_dm) + (0.01283 * p_wc_cm) + (0.459 * p_smoke);
            SET v_compare_score = (0.08372 * p_age) + (0.05988 * p_sex) + (0.02034 * v_compare_sbp) + (0.01283 * v_compare_wc);
            
            SET v_predicted_risk = 1 - POW(v_sur_root, EXP(v_full_score - 7.31047));
            SET v_compare_risk = 1 - POW(v_sur_root, EXP(v_compare_score - 7.31047));
        END IF;

        -- คำนวณอัตราส่วนความเสี่ยง (Risk Ratio)
        IF v_compare_risk > 0 THEN
            SET v_risk_ratio = ROUND(v_predicted_risk / v_compare_risk, 1);
        END IF;

        -- จัดกลุ่มระดับความเสี่ยง
        IF v_predicted_risk < 0.1 THEN
            SET v_risk_group_th = 'กลุ่มเสี่ยงน้อย';
            SET v_risk_group_en = 'low risk';
        ELSEIF v_predicted_risk >= 0.1 AND v_predicted_risk < 0.2 THEN
            SET v_risk_group_th = 'กลุ่มเสี่ยงปานกลาง';
            SET v_risk_group_en = 'medium risk';
        ELSEIF v_predicted_risk >= 0.2 AND v_predicted_risk <= 0.3 THEN
            SET v_risk_group_th = 'กลุ่มเสี่ยงสูง';
            SET v_risk_group_en = 'high risk';
        ELSEIF v_predicted_risk > 0.3 THEN
            SET v_risk_group_th = 'กลุ่มเสี่ยงสูงมาก';
            SET v_risk_group_en = 'very high risk';
        END IF;

        -- หมายเหตุกรณีสำเร็จ
        SET v_note = CONCAT('ประมวลผลสำเร็จ โดยใช้สูตร ', v_method);
    END IF;

    -- ==========================================
    -- 3. RETURN STRING WITH '|' DELIMITER
    -- ==========================================
    RETURN CONCAT_WS('|',
        v_status,
        v_method,
        ROUND(v_predicted_risk * 100, 2),
        ROUND(v_compare_risk * 100, 2),
        v_risk_ratio,
        v_risk_group_th,
        v_risk_group_en,
        v_note
    );

END //

DELIMITER ;
