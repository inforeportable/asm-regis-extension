# คู่มือการติดตั้งและการใช้งาน Thai ASCVD Risk Score (MySQL Function)

ระบบประมวลผลประเมินความเสี่ยงต่อการเกิดโรคหลอดเลือดหัวใจ (Thai CV Risk Score 2.5) พัฒนาขึ้นสำหรับใช้งานบน **MySQL Database** ในรูปแบบ **Stored Function** ประมวลผลและส่งผลลัพธ์กลับมาเป็น String คั่นด้วยเครื่องหมาย Pipe (`|`)

---

## 1. รายละเอียดและการวิเคราะห์การทำงาน (Calculation Logic)

ระบบรองรับการคำนวณความเสี่ยงโดยปรับลำดับการเลือกใช้สูตรคำนวณอัตโนมัติ 3 แบบ ตามความสมบูรณ์ของข้อมูลผู้ป่วย:

```
                  [ตรวจสอบข้อมูล Input]
                            │
               ┌────────────┴────────────┐
               │ มีค่า Total Cholesterol? │
               └────────────┬────────────┘
                       YES  │  NO
        ┌───────────────────┴───────────────────┐
        ▼                                       ▼
  [สูตร 1: TC]                   ┌─────────────────────────────┐
 (ใช้ผลเลือด TC)                   │ มีรอบเอว (WC) และส่วนสูง?  │
                                 └──────────────┬──────────────┘
                                         YES    │    NO
                          ┌─────────────────────┴─────────────────────┐
                          ▼                                           ▼
                    [สูตร 2: WHR]                               [สูตร 3: WC]
               (อัตราส่วนรอบเอว/ส่วนสูง)                         (ใช้ค่ารอบเอว)
```

---

### 1.1 ค่ามาตรฐานเปรียบเทียบ (Baseline Comparison)
ระบบจะกำหนดค่ามาตรฐานเปรียบเทียบตามเพศและอายุของผู้ป่วย เพื่อคำนวณระดับความเสี่ยงของคนปกติในกลุ่มเดียวกัน (`compare_risk`):

| เพศ | อายุ (ปี) | ค่า SBP เปรียบเทียบ (`compare_sbp`) | ค่า WC เปรียบเทียบ (`compare_wc`) | ค่า WHR เปรียบเทียบ (`compare_whr`) |
| :---: | :---: | :---: | :---: | :---: |
| **ชาย (1)** | $\le$ 60 | 120 mmHg | 93 cm | 0.58125 |
| **ชาย (1)** | > 60 | 132 mmHg | 93 cm | 0.58125 |
| **หญิง (0)** | $\le$ 60 | 115 mmHg | 79 cm | 0.52667 |
| **หญิง (0)** | > 60 | 130 mmHg | 79 cm | 0.52667 |

---

### 1.2 สมการที่ใช้คำนวณ (Formulae)

ค่าอัตราการรอดชีวิตอ้างอิง: $S_0(t) = 0.964588$

#### **สูตร 1: Total Cholesterol (TC)**
$$\text{Full Score} = (0.08183 \times \text{Age}) + (0.39499 \times \text{Sex}) + (0.02084 \times \text{SBP}) + (0.69974 \times \text{DM}) + (0.00212 \times \text{TC}) + (0.41916 \times \text{Smoke})$$$$\text{Predicted Risk} = 1 - (0.964588)^{\exp(\text{Full Score} - 7.04423)}$$

#### **สูตร 2: Waist-to-Height Ratio (WHR)**$$\text{WHR} = \frac{\text{รอบเอว (cm)}}{\text{ส่วนสูง (cm)}}$$$$\text{Full Score} = (0.079 \times \text{Age}) + (0.128 \times \text{Sex}) + (0.019350987 \times \text{SBP}) + (0.58454 \times \text{DM}) + (3.512566 \times \text{WHR}) + (0.459 \times \text{Smoke})$$$$\text{Predicted Risk} = 1 - (0.964588)^{\exp(\text{Full Score} - 7.712325)}$$
#### **สูตร 3: Waist Circumference (WC)**$$\text{Full Score} = (0.08372 \times \text{Age}) + (0.05988 \times \text{Sex}) + (0.02034 \times \text{SBP}) + (0.59953 \times \text{DM}) + (0.01283 \times \text{WC}) + (0.459 \times \text{Smoke})$$
$$\text{Predicted Risk} = 1 - (0.964588)^{\exp(\text{Full Score} - 7.31047)}$$

---

### 1.3 การแปลผลและการจัดกลุ่มความเสี่ยง (Risk Level Classification)

* **ความเสี่ยงเป็นเท่า (`risk_ratio_times`)**: คำนวณจาก $\frac{\text{Predicted Risk}}{\text{Compare Risk}}$
* **ระดับความเสี่ยง**:
  * `< 10%`: **กลุ่มเสี่ยงน้อย** (`low risk`)
  * `10% - 19.9%`: **กลุ่มเสี่ยงปานกลาง** (`medium risk`)
  * `20% - 30%`: **กลุ่มเสี่ยงสูง** (`high risk`)
  * `> 30%`: **กลุ่มเสี่ยงสูงมาก** (`very high risk`)

---

## 2. ข้อมูลพารามิเตอร์ Input และ Output

### 2.1 พารามิเตอร์นำเข้า (Input Parameters)

| ลำดับ | พารามิเตอร์ | ชนิดข้อมูล | เงื่อนไข / ค่าที่รองรับ |
| :---: | :--- | :--- | :--- |
| 1 | `p_age` | `INT` | อายุ (ปี) [ต้อง > 0] |
| 2 | `p_sex` | `INT` | เพศ (`0` = หญิง, `1` = ชาย) |
| 3 | `p_smoke` | `INT` | สถานะสูบบุหรี่ (`0` = ไม่สูบ, `1` = สูบ) |
| 4 | `p_dm` | `INT` | ประวัติโรคเบาหวาน (`0` = ไม่เป็น, `1` = เป็น) |
| 5 | `p_sbp` | `INT` | ความดันโลหิต Systolic (mmHg) [ต้อง $\ge$ 70] |
| 6 | `p_tc` | `INT` | Total Cholesterol (mg/dL) [ระบุ 0 หรือ NULL หากไม่มี] |
| 7 | `p_wc_cm` | `DOUBLE` | เส้นรอบเอว (ซม.) [ระบุ 0 หรือ NULL หากไม่มี] |
| 8 | `p_height_cm` | `DOUBLE` | ส่วนสูง (ซม.) [ระบุ 0 หรือ NULL หากไม่มี] |

---

### 2.2 ผลลัพธ์ส่งกลับ (Output String)

ฟังก์ชันจะส่งคืนข้อความ String โดยใช้เครื่องหมาย Pipe (`|`) เป็นตัวคั่น จำนวน 8 ฟิลด์:

```text
status|method_used|predicted_risk_percent|compare_risk_percent|risk_ratio_times|risk_group_th|risk_group_en|note
```

| ลำดับฟิลด์ | ชื่อฟิลด์ | ตัวอย่างค่า | คำอธิบาย |
| :---: | :--- | :--- | :--- |
| **1** | `status` | `1` หรือ `0` | **1** = ประมวลผลสำเร็จ / **0** = เกิดข้อผิดพลาด |
| **2** | `method_used` | `TC`, `WHR`, `WC`, `NONE` | สูตรที่ใช้ในการคำนวณ |
| **3** | `predicted_risk_percent` | `12.50` | โอกาสเกิดโรคหลอดเลือดหัวใจใน 10 ปี (%) |
| **4** | `compare_risk_percent` | `5.08` | ความเสี่ยงเปรียบเทียบของคนปกติในกลุ่มอายุเดียวกัน (%) |
| **5** | `risk_ratio_times` | `2.5` | ระดับความเสี่ยงเทียบเป็นจำนวนเท่าของคนปกติ |
| **6** | `risk_group_th` | `กลุ่มเสี่ยงปานกลาง` | แปลผลระดับความเสี่ยง (ภาษาไทย) |
| **7** | `risk_group_en` | `medium risk` | แปลผลระดับความเสี่ยง (ภาษาอังกฤษ) |
| **8** | `note` | `ประมวลผลสำเร็จ...` | ข้อความแจ้งความสำเร็จ หรือ รายละเอียด Error |

---

## 3. สคริปต์สำหรับการติดตั้ง (Installation Script)

รันคำสั่ง SQL ด้านล่างนี้ใน MySQL Database Client (เช่น MySQL Workbench, phpMyAdmin, DBeaver) เพื่อสร้าง Function:

```sql mysql_thai_ascvd_fn.sql
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
```

---

## 4. ตัวอย่างการใช้งาน (Usage Examples)

### 4.1 การเรียกใช้งานแบบ Direct Call

```sql
-- กรณีที่ 1: มีค่า TC (ชาย, อายุ 50, ไม่สูบบุหรี่, ไม่เป็นเบาหวาน, SBP 130, TC 210)
SELECT fn_calc_thai_ascvd(50, 1, 0, 0, 130, 210, 0, 0) AS result;
-- Output: 1|TC|6.33|5.08|1.2|กลุ่มเสี่ยงน้อย|low risk|ประมวลผลสำเร็จ โดยใช้สูตร TC

-- กรณีที่ 2: ไม่มี TC ใช้ WHR แทน (ชาย, อายุ 50, สูบบุหรี่, SBP 140, เอว 85 ซม., สูง 170 ซม.)
SELECT fn_calc_thai_ascvd(50, 1, 1, 0, 140, 0, 85, 170) AS result;
-- Output: 1|WHR|12.21|7.18|1.7|กลุ่มเสี่ยงปานกลาง|medium risk|ประมวลผลสำเร็จ โดยใช้สูตร WHR

-- กรณีที่ 3: ข้อมูลไม่ครบถ้วน (ไม่ใส่ทั้ง TC และ รอบเอว)
SELECT fn_calc_thai_ascvd(50, 1, 0, 0, 130, 0, 0, 0) AS result;
-- Output: 0|NONE|0|0|0|-|-|ข้อมูลไม่ครบถ้วน: ต้องระบุค่า Total Cholesterol (TC) หรือ รอบเอว (WC) อย่างน้อย 1 ค่า
```

---

### 4.2 การดึงข้อมูลแยกคอลัมน์จากตารางจริง (Query Parsing)

เมื่อนำไปใช้กับตารางข้อมูลผู้ป่วย สามารถใช้ฟังก์ชัน `SUBSTRING_INDEX` เพื่อแยกคอลัมน์จาก String Output ได้ดังนี้:

```sql
SELECT 
    patient_id,
    patient_name,
    -- เรียกใช้ฟังก์ชัน
    @res := fn_calc_thai_ascvd(age, sex, is_smoker, is_dm, sbp, tc, waist_cm, height_cm) AS raw_output,
    
    -- แยกคอลัมน์ออกมาใช้งาน
    SUBSTRING_INDEX(@res, '|', 1) AS status,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 2), '|', -1) AS method_used,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 3), '|', -1) AS predicted_risk_percent,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 6), '|', -1) AS risk_group_th,
    SUBSTRING_INDEX(@res, '|', -1) AS note
FROM patient_screening_data;
```
