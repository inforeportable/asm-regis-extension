# คู่มือการติดตั้งและการใช้งาน HDC CVD Risk Calculator (`fnc_cvd_risk_hdc`)

ระบบประมวลผลประเมินความเสี่ยงโรคหัวใจและหลอดเลือด **Thai ASCVD Score 2 (เกณฑ์ HDC)** พัฒนาเป็น **MySQL Stored Function** ที่ส่งผลลัพธ์กลับมาเป็นข้อความ String คั่นด้วยเครื่องหมาย Pipe (`|`) เพื่อความสะดวกในการนำไปใช้งานต่อในระบบ Health Data Center (HDC), SQL Query หรือ Web API

---

## 1. รายละเอียดและการวิเคราะห์การทำงาน (Calculation Logic)

ระบบรองรับการคำนวณความเสี่ยง 2 กรณี โดยเลือกสูตรประมวลผลให้อัตโนมัติตามความสมบูรณ์ของข้อมูล:

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
 (ใช้ผลตรวจเลือด)                  │  มีค่ารอบเอว และ ส่วนสูง?   │
                                 └──────────────┬──────────────┘
                                         YES    │    NO
                          ┌─────────────────────┴─────────────────────┐
                          ▼                                           ▼
                    [สูตร 2: WHR]                              [ERROR]
               (อัตราส่วนรอบเอว/ส่วนสูง)                     (ข้อมูลไม่ครบถ้วน)
```

---

### 1.1 สมการที่ใช้คำนวณ (HDC Model)

* ค่าอ้างอิงอัตรารอดชีวิต (Baseline Survival Rate): $S_0(t) = 0.978296$

#### **กรณีที่ 1: มีค่า Total Cholesterol (สูตร TC)**
$$\text{FullScore} = (0.08183 \times \text{AGE}) + (0.39499 \times \text{SEX}) + (0.02084 \times \text{SBP}) + (0.69974 \times \text{DM}) + (0.00212 \times \text{CHOL}) + (0.41916 \times \text{SMOKING})$$$$P_{\text{FullScore}}(\%) = \left( 1 - (0.978296)^{\exp(\text{FullScore} - 7.04423)} \right) \times 100$$
#### **กรณีที่ 2: ไม่มีค่า Total Cholesterol (สูตร WHR)**$$\text{WHR} = \frac{\text{Waist (รอบเอว ซม.)}}{\text{Height (ส่วนสูง ซม.)}}$$$$\text{FullScore} = (0.079 \times \text{AGE}) + (0.128 \times \text{SEX}) + (0.019350987 \times \text{SBP}) + (0.58454 \times \text{DM}) + (3.512566 \times \text{WHR}) + (0.459 \times \text{SMOKING})$$$$P_{\text{FullScore}}(\%) = \left( 1 - (0.978296)^{\exp(\text{FullScore} - 7.720484)} \right) \times 100$$

---

### 1.2 เกณฑ์การประเมินระดับความเสี่ยง (Risk Level Classification)

ระบบแบ่งระดับความเสี่ยงออกเป็น **5 ระดับ** ตามเกณฑ์มาตรฐาน HDC:

| ค่าเปอร์เซ็นต์ความเสี่ยง ($P_{\text{FullScore}}$) | ระดับความเสี่ยง (`risk_level`) | ข้อความภาษาไทย (`risk_group_th`) | ข้อความภาษาอังกฤษ (`risk_group_en`) |
| :---: | :---: | :--- | :--- |
| **< 10%** | `1` | ระดับ 1: ความเสี่ยงต่ำ | Level 1: Low Risk |
| **10% - < 20%** | `2` | ระดับ 2: ความเสี่ยงปานกลาง | Level 2: Medium Risk |
| **20% - < 30%** | `3` | ระดับ 3: ความเสี่ยงสูง | Level 3: High Risk |
| **30% - < 40%** | `4` | ระดับ 4: ความเสี่ยงสูงมาก | Level 4: Very High Risk |
| **>= 40%** | `5` | ระดับ 5: ความเสี่ยงสูงอันตราย | Level 5: Critical Risk |

---

## 2. ข้อมูลพารามิเตอร์ Input และ Output

### 2.1 พารามิเตอร์นำเข้า (Input Parameters)

| ลำดับ | พารามิเตอร์ | ชนิดข้อมูล | คำอธิบาย / เงื่อนไข |
| :---: | :--- | :--- | :--- |
| 1 | `p_age` | `INT` | AGE: อายุ (ปี) [ต้อง > 0] |
| 2 | `p_sex` | `INT` | SEX: เพศ (`1` = ชาย, `0` = หญิง) |
| 3 | `p_smoke` | `INT` | SMOKING: พฤติกรรมการสูบบุหรี่ (`1` = สูบ, `0` = ไม่สูบ) |
| 4 | `p_dm` | `INT` | DM: ประวัติโรคเบาหวาน (`1` = เป็น, `0` = ไม่เป็น) |
| 5 | `p_sbp` | `INT` | SBP: ความดันโลหิตตัวบน (mmHg) [ต้อง $\ge$ 70] |
| 6 | `p_chol` | `INT` | CHOL: Total Cholesterol (mg/dL) [ใส่ 0 หรือ NULL หากไม่มี] |
| 7 | `p_waist` | `DOUBLE` | Waist: เส้นรอบเอว (ซม.) [ใส่ 0 หรือ NULL หากไม่มี] |
| 8 | `p_height` | `DOUBLE` | Height: ส่วนสูง (ซม.) [ใส่ 0 หรือ NULL หากไม่มี] |

---

### 2.2 ผลลัพธ์ส่งกลับ (Output String Format)

ฟังก์ชันส่งคืนข้อความ String โดยใช้เครื่องหมาย Pipe (`|`) คั่นจำนวน 7 ฟิลด์:

```text
status|method_used|predicted_risk_percent|risk_level|risk_group_th|risk_group_en|note
```

| ลำดับฟิลด์ | ชื่อฟิลด์ | ตัวอย่างค่า | คำอธิบาย |
| :---: | :--- | :--- | :--- |
| **1** | `status` | `1` หรือ `0` | **1** = ประมวลผลสำเร็จ / **0** = เกิดข้อผิดพลาด |
| **2** | `method_used` | `TC`, `WHR`, `NONE` | สูตรที่ใช้คำนวณ (`TC` = ผลเลือด, `WHR` = สัดส่วนร่างกาย) |
| **3** | `predicted_risk_percent` | `18.84` | เปอร์เซ็นต์ความเสี่ยง $P_{\text{FullScore}}(\%)$ (ทศนิยม 2 ตำแหน่ง) |
| **4** | `risk_level` | `1` - `5` | รหัสระดับความเสี่ยง (1 ถึง 5) |
| **5** | `risk_group_th` | `ระดับ 2: ความเสี่ยงปานกลาง` | ผลแปลระดับความเสี่ยงภาษาไทย |
| **6** | `risk_group_en` | `Level 2: Medium Risk` | ผลแปลระดับความเสี่ยงภาษาอังกฤษ |
| **7** | `note` | `ประมวลผลสำเร็จ...` | ข้อความแจ้งสำเร็จ หรือ รายละเอียดสาเหตุ Error |

---

## 3. สคริปต์สำหรับการติดตั้ง (Installation SQL Script)

คัดลอกคำสั่ง SQL ด้านล่างไปรันใน MySQL Database Server:

```sql mysql_hdc_cvd_risk_fn.sql
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

        -- ป้องกันค่าติดลบ
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
```

---

## 4. ตัวอย่างการใช้งานและผลลัพธ์ (Examples)

### 4.1 เรียกใช้งานตรงด้วยคำสั่ง SELECT

**ตัวอย่างที่ 1: กรณีใช้ผลเลือด TC (ความเสี่ยงปานกลาง)**
```sql
SELECT fnc_cvd_risk_hdc(55, 1, 1, 1, 140, 230, 0, 0) AS result;
```
* **Output:** `1|TC|18.84|2|ระดับ 2: ความเสี่ยงปานกลาง|Level 2: Medium Risk|ประมวลผลสำเร็จ โดยใช้สูตร HDC (TC)`

**ตัวอย่างที่ 2: กรณีไม่มี TC ใช้สัดส่วนร่างกาย WHR**
```sql
SELECT fnc_cvd_risk_hdc(62, 0, 0, 1, 150, 0, 90, 155) AS result;
```
* **Output:** `1|WHR|13.88|2|ระดับ 2: ความเสี่ยงปานกลาง|Level 2: Medium Risk|ประมวลผลสำเร็จ โดยใช้สูตร HDC (WHR)`

**ตัวอย่างที่ 3: กรณีความเสี่ยงสูงอันตราย ($\ge$ 40%)**
```sql
SELECT fnc_cvd_risk_hdc(68, 1, 1, 1, 175, 280, 0, 0) AS result;
```
* **Output:** `1|TC|43.25|5|ระดับ 5: ความเสี่ยงสูงอันตราย|Level 5: Critical Risk|ประมวลผลสำเร็จ โดยใช้สูตร HDC (TC)`

**ตัวอย่างที่ 4: กรณีข้อมูลไม่สมบูรณ์ (Error)**
```sql
SELECT fnc_cvd_risk_hdc(50, 1, 0, 0, 130, 0, 0, 0) AS result;
```
* **Output:** `0|NONE|0.00|0|-|-|ข้อมูลไม่ครบถ้วน: ต้องระบุค่า Total Cholesterol (CHOL) หรือ (รอบเอว และ ส่วนสูง)`

---

### 4.2 การดึงข้อมูลแยกคอลัมน์จากตารางจริง

```sql
SELECT 
    cid,
    patient_name,
    -- เรียกใช้ฟังก์ชัน
    @res := fnc_cvd_risk_hdc(age, sex, smoking, dm, sbp, chol, waist, height) AS raw_result,
    
    -- แยกข้อมูลออกมาเป็นคอลัมน์ด้วย SUBSTRING_INDEX
    SUBSTRING_INDEX(@res, '|', 1) AS status,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 2), '|', -1) AS method_used,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 3), '|', -1) AS risk_percent,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 4), '|', -1) AS risk_level,
    SUBSTRING_INDEX(SUBSTRING_INDEX(@res, '|', 5), '|', -1) AS risk_group_th,
    SUBSTRING_INDEX(@res, '|', -1) AS note
FROM hdc_patient_screening;
```
