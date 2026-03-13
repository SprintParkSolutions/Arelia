/**
 * @description InvoiceService
 * -----------------------------------------------------------------------------
 * Service class used by the Invoice Builder LWC to:
 *  1) Load the latest Invoice data (Draft first, otherwise latest Submitted)
 *  2) Save the Invoice as Draft (creates/updates Invoice__c + child rows)
 *  3) Submit the Invoice (locks Opportunity to avoid duplicate versions,
 *     assigns Version_No__c + Previous_Invoice__c, generates PDF asynchronously)
 *
 * Data model used:
 *  - Invoice__c (header + totals + status + versioning)
 *  - Invoice_Line__c (section rows + item rows)
 *  - Invoice_Material__c (materials list)
 *  - Invoice_Not_Included__c (not included list)
 *
 * Notes:
 *  - LWC sends/receives DTO payloads (HeaderDTO/SectionDTO/LineDTO/etc.)
 *  - Child rows are replaced on every save/submit for consistency
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation')
public with sharing class InvoiceService {

    // =========================
    // Constants
    // =========================
    private static final String STATUS_DRAFT     = 'Draft';
    private static final String STATUS_SUBMITTED = 'Submitted';
    private static final String DEFAULT_SECTION_TYPE = 'Other Works';

    private static final String TYPE_WOOD        = 'WOOD';
    private static final String TYPE_ELECTRICAL  = 'ELECTRICAL';
    private static final String TYPE_OTHER       = 'OTHER';

    private static final String ELEC_MODE_QTY    = 'QTY';
    private static final String ELEC_MODE_COILS  = 'COILS';

    // =========================
    // DTOs
    // =========================

    /**
     * @description HeaderDTO
     * Holds Invoice header fields shown in the UI header section.
     * These values map to Invoice__c fields.
     */
    public class HeaderDTO {
        @AuraEnabled public String  clientName;      // Invoice__c.Client_Name__c
        @AuraEnabled public String  phone;           // Invoice__c.Phone__c
        @AuraEnabled public String  clientAddress;   // Invoice__c.Address__c
        @AuraEnabled public Date    invoiceDate;     // Invoice__c.Invoice_Date__c
        @AuraEnabled public String  invoiceNo;       // Invoice__c.Invoice_No__c
        @AuraEnabled public Decimal gstPercent;      // Invoice__c.GST_Percent__c
    }

    /**
     * @description LineDTO
     * Represents one line item inside a section (NOT the section header row).
     * Depending on section type, only some fields are used:
     *  - WOOD/CIVIL: l, h, qty, rate
     *  - ELECTRICAL: electricalMode + (coils/meters OR qty) + rate
     *  - OTHER: amount (manual amount), no dimensions/rate
     */
    public class LineDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String category;
        @AuraEnabled public String item;
        @AuraEnabled public String brand;
        @AuraEnabled public String explanation;

        // WOOD-LIKE (WOOD + CIVIL WORK)
        @AuraEnabled public Decimal l;
        @AuraEnabled public Decimal h;
        @AuraEnabled public Decimal qty;

        // ELECTRICAL
        @AuraEnabled public String  electricalMode; // COILS or QTY
        @AuraEnabled public Decimal coils;
        @AuraEnabled public Decimal meters;

        // COMMON
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal amount; // used for OTHER as manual amount
    }

    /**
     * @description SectionDTO
     * Represents a section block in the UI (e.g., Wood Work, Electrical, Other Works).
     * Each section has:
     *  - A section header row (stored in Invoice_Line__c with Is_Section__c=true)
     *  - Multiple line items (stored in Invoice_Line__c with Is_Section__c=false)
     */
    public class SectionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String sectionName;
        @AuraEnabled public String sectionType; // picklist value stored on each line (Section_Type__c)
        @AuraEnabled public List<LineDTO> lines;
        @AuraEnabled public Decimal subtotal;   // computed client-side or rebuilt from DB
    }

    /**
     * @description MaterialDTO
     * Represents one Material row (Invoice_Material__c) shown in Materials section.
     */
    public class MaterialDTO {
        @AuraEnabled public String  material;
        @AuraEnabled public String  brand;
        @AuraEnabled public String  grade;
        @AuraEnabled public Integer sortOrder;
    }

    /**
     * @description NotIncludedDTO
     * Represents one "Not Included" row (Invoice_Not_Included__c).
     */
    public class NotIncludedDTO {
        @AuraEnabled public String  text;
        @AuraEnabled public Integer sortOrder;
    }

    /**
     * @description PayloadDTO
     * Full payload sent from the UI to Apex for Draft/Submit operations.
     * Includes:
     *  - parent Opportunity Id
     *  - optional existing invoice Id (for updating draft)
     *  - header + sections + materials + not included
     *  - totals computed in UI (Total, GST, Grand Total)
     */
    public class PayloadDTO {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Id existingInvoiceId;

        @AuraEnabled public HeaderDTO header;
        @AuraEnabled public List<SectionDTO> sections;

        @AuraEnabled public List<MaterialDTO> materials;
        @AuraEnabled public List<NotIncludedDTO> notIncluded;

        @AuraEnabled public Decimal total;
        @AuraEnabled public Decimal gstAmount;
        @AuraEnabled public Decimal grandTotal;
    }

    /**
     * @description InitDTO
     * Response object returned to UI when the screen loads.
     * Contains the invoice id (draft or latest submitted) and all child data.
     */
    public class InitDTO {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String status;     // Draft / Submitted
        @AuraEnabled public Integer versionNo; // Invoice__c.Version_No__c as Integer for UI

        @AuraEnabled public HeaderDTO header;
        @AuraEnabled public List<SectionDTO> sections;
        @AuraEnabled public List<MaterialDTO> materials;
        @AuraEnabled public List<NotIncludedDTO> notIncluded;
    }

    // =========================
    // INIT
    // =========================

    /**
     * @description init
     * Loads invoice data for an Opportunity:
     *  - If a Draft exists, returns the latest Draft
     *  - Otherwise returns the latest Submitted invoice
     * Also loads child records and converts them into DTO format used by the UI.
     *
     * @param opportunityId Opportunity Id selected in the UI
     * @return InitDTO invoice header + sections + materials + not included
     */
    @AuraEnabled
    public static InitDTO init(Id opportunityId) {
        InitDTO resp = new InitDTO();
        if (opportunityId == null) {return resp;}

        Invoice__c inv = findDraftOrLatestSubmitted(opportunityId);
        if (inv == null) {return resp;}

        resp.invoiceId = inv.Id;
        resp.status = inv.Status__c;

        // Version_No__c is a Number field -> Decimal in Apex -> convert to Integer for UI display
        resp.versionNo = (inv.Version_No__c == null) ? null : inv.Version_No__c.intValue();

        resp.header = new HeaderDTO();
        resp.header.clientName    = inv.Client_Name__c;
        resp.header.phone         = inv.Phone__c;
        resp.header.clientAddress = inv.Address__c;
        resp.header.invoiceDate   = inv.Invoice_Date__c;
        resp.header.invoiceNo     = inv.Invoice_No__c;
        resp.header.gstPercent    = inv.GST_Percent__c;

        List<Invoice_Line__c> dbLines = [SELECT Is_Section__c, Section_Name__c, Section_Type__c,Electrical_Mode__c,
                    Item__c, Category__c, Brand__c, Explanation__c, L__c, H__c, Qty__c, Coils__c, Meters__c,
                    Rate__c, Amount__c, Sort_Order__c, Area_Sqft__c
                    FROM Invoice_Line__c WHERE Invoice__c = :inv.Id ORDER BY Sort_Order__c];
        resp.sections = toSections(dbLines);

        resp.materials = new List<MaterialDTO>();
        for (Invoice_Material__c m : [SELECT Material__c, Brand__c, Grade__c, Sort_Order__c
                        FROM Invoice_Material__c WHERE Invoice__c = :inv.Id ORDER BY Sort_Order__c])
        {
            MaterialDTO dto = new MaterialDTO();
            dto.material = m.Material__c;
            dto.brand = m.Brand__c;
            dto.grade = m.Grade__c;
            dto.sortOrder = (m.Sort_Order__c == null) ? null : m.Sort_Order__c.intValue();
            resp.materials.add(dto);
        }

        resp.notIncluded = new List<NotIncludedDTO>();
        for (Invoice_Not_Included__c n : [SELECT Text__c, Sort_Order__c FROM Invoice_Not_Included__c
                    WHERE Invoice__c = :inv.Id ORDER BY Sort_Order__c])
        {
            NotIncludedDTO dto = new NotIncludedDTO();
            dto.text = n.Text__c;
            dto.sortOrder = (n.Sort_Order__c == null) ? null : n.Sort_Order__c.intValue();
            resp.notIncluded.add(dto);
        }

        return resp;
    }

    // =========================
    // JSON endpoints
    // =========================

    /**
     * @description saveDraftJson
     * Wrapper method for LWC to save Draft using JSON payload.
     *
     * @param payloadJson JSON string matching PayloadDTO structure
     * @return Id of the Draft Invoice__c record
     */
    @AuraEnabled
    public static Id saveDraftJson(String payloadJson) {
        PayloadDTO p = parsePayload(payloadJson);
        return saveDraft(p);
    }

    /**
     * @description submitJson
     * Submits an invoice:
     *  - Validates payload
     *  - Locks Opportunity (FOR UPDATE) to avoid version collisions
     *  - Determines previous submitted invoice
     *  - Computes next version number
     *  - Converts draft to submitted OR creates a new submitted invoice
     *  - Replaces child records
     *  - Enqueues PDF generation job
     *
     * @param payloadJson JSON string matching PayloadDTO structure
     * @return Id of the Submitted Invoice__c record
     */
    @AuraEnabled
    public static Id submitJson(String payloadJson) {
        PayloadDTO payload = (PayloadDTO) JSON.deserialize(payloadJson, PayloadDTO.class);
        validate(payload);

        // Lock the Opportunity to prevent two submits creating same version
        Opportunity oppLock = [SELECT Id FROM Opportunity WHERE Id = :payload.opportunityId FOR UPDATE];

        // Determine previous submitted invoice (by CreatedDate, not by Version)
        Invoice__c prevSubmitted = getLatestSubmittedByCreated(payload.opportunityId);

        // Determine next version number (MAX(version)+1 OR COUNT+1 for old data)
        Integer nextVersion = getNextVersionNumber(payload.opportunityId);

        if (payload.existingInvoiceId != null) {

            List<Invoice__c> invList = [SELECT Id, Status__c, Opportunity__c
                FROM Invoice__c WHERE Id = :payload.existingInvoiceId FOR UPDATE];

            if (invList.isEmpty()) {throw new AuraHandledException('Draft invoice not found.');}

            Invoice__c inv = invList[0];

            if (inv.Opportunity__c != payload.opportunityId) {
                throw new AuraHandledException('Draft invoice does not belong to this Opportunity.');
            }

            // If already submitted, do not resubmit
            if (inv.Status__c == STATUS_SUBMITTED) {return inv.Id;}

            // Convert draft -> submitted
            inv.Status__c = STATUS_SUBMITTED;

            // Set Version + Previous Invoice link
            inv.Version_No__c = nextVersion;
            inv.Previous_Invoice__c = (prevSubmitted == null ? null : prevSubmitted.Id);

            applyHeaderAndTotals(inv, payload);
            update inv;

            replaceChildren(inv.Id, payload);

            System.enqueueJob(new InvoicePdfJob(inv.Id));
            return inv.Id;
        }

        // New submitted invoice
        Invoice__c newInv = new Invoice__c();
        newInv.Opportunity__c = payload.opportunityId;
        newInv.Status__c = STATUS_SUBMITTED;

        newInv.Version_No__c = nextVersion;
        newInv.Previous_Invoice__c = (prevSubmitted == null ? null : prevSubmitted.Id);

        applyHeaderAndTotals(newInv, payload);
        insert newInv;

        replaceChildren(newInv.Id, payload);
        System.enqueueJob(new InvoicePdfJob(newInv.Id));

        return newInv.Id;
    }

    // =========================
    // Payload parsing / validation
    // =========================

    /**
     * @description parsePayload
     * Safely deserializes the JSON payload into PayloadDTO and ensures required structures exist.
     * Throws AuraHandledException with user-friendly message for UI.
     *
     * @param payloadJson JSON string from UI
     * @return PayloadDTO normalized payload
     */
    private static PayloadDTO parsePayload(String payloadJson) {
        if (String.isBlank(payloadJson)) {throw new AuraHandledException('PayloadJson is missing.');}
        PayloadDTO p;
        try {
            p = (PayloadDTO) JSON.deserialize(payloadJson, PayloadDTO.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Payload parse failed: ' + ex.getMessage());
        }
        if (p == null || p.opportunityId == null) {throw new AuraHandledException('OpportunityId is required.');}

        if (p.header == null) {p.header = new HeaderDTO();}
        if (p.sections == null) {p.sections = new List<SectionDTO>();}
        if (p.materials == null) {p.materials = new List<MaterialDTO>();}
        if (p.notIncluded == null) {p.notIncluded = new List<NotIncludedDTO>();}
        return p;
    }

    /**
     * @description validate
     * Ensures payload has required attributes and initializes missing collections to avoid null errors.
     *
     * @param p PayloadDTO from UI
     */
    private static void validate(PayloadDTO p) {
        if (p == null || p.opportunityId == null) {throw new AuraHandledException('OpportunityId is required.');}
        if (p.header == null) {p.header = new HeaderDTO();}
        if (p.sections == null) {p.sections = new List<SectionDTO>();}
        if (p.materials == null) {p.materials = new List<MaterialDTO>();}
        if (p.notIncluded == null) {p.notIncluded = new List<NotIncludedDTO>();}
    }

    // =========================
    // Draft save
    // =========================

    /**
     * @description saveDraft
     * Saves invoice as Draft:
     *  - Reuses an existing draft for the opportunity (latest) OR creates a new one
     *  - Updates header/totals
     *  - Replaces all child records (lines/materials/not included)
     *
     * @param payload Complete payload from UI
     * @return Id of the Draft Invoice__c record
     */
    public static Id saveDraft(PayloadDTO payload) {
        validate(payload);

        Id targetId = payload.existingInvoiceId;

        // If UI didn't pass existingInvoiceId, reuse latest draft for same Opportunity
        if (targetId == null) {
            List<Invoice__c> drafts = [SELECT Id FROM Invoice__c WHERE Opportunity__c = :payload.opportunityId
                    AND Status__c =: STATUS_DRAFT ORDER BY LastModifiedDate DESC LIMIT 1];
            if (!drafts.isEmpty()) {targetId = drafts[0].Id;}
        }

        Boolean isInsert = (targetId == null);

        Invoice__c inv = isInsert ? new Invoice__c() : new Invoice__c(Id = targetId);
        inv.Opportunity__c = payload.opportunityId;
        inv.Status__c = STATUS_DRAFT;
        applyHeaderAndTotals(inv, payload);

        if (isInsert) {insert inv;}
        else {update inv;}

        replaceChildren(inv.Id, payload);
        return inv.Id;
    }

    // =========================
    // Header + totals mapping
    // =========================

    /**
     * @description applyHeaderAndTotals
     * Maps header fields and totals from PayloadDTO into Invoice__c before DML.
     *
     * @param inv Invoice__c to populate
     * @param p   PayloadDTO from UI
     */
    private static void applyHeaderAndTotals(Invoice__c inv, PayloadDTO p) {
        inv.Client_Name__c = p.header.clientName;
        inv.Phone__c = p.header.phone;
        inv.Address__c = p.header.clientAddress;
        inv.Invoice_Date__c = p.header.invoiceDate;
        inv.Invoice_No__c = p.header.invoiceNo;

        inv.GST_Percent__c = p.header.gstPercent;
        inv.Total__c = p.total;
        inv.GST_Amount__c = p.gstAmount;
        inv.Grand_Total__c = p.grandTotal;
    }

    /**
     * @description canonType
     * Converts a UI picklist value (or text) into a canonical internal type:
     *  - WOOD (includes CIVIL)
     *  - ELECTRICAL
     *  - OTHER
     *
     * @param raw Raw Section Type string from UI
     * @return canonical type string
     */
    private static String canonType(String raw) {
        String t = String.isBlank(raw) ? '' : raw.trim().toUpperCase();
        if (t == TYPE_WOOD || t.contains('WOOD')) {return TYPE_WOOD;}
        if (t.contains('ELECTRIC')) {return TYPE_ELECTRICAL;}
        if (t.contains('CIVIL')) {return TYPE_WOOD;}
        if (t.contains('OTHER')) {return TYPE_OTHER;}
        return TYPE_OTHER;
    }

    /**
     * @description nz
     * Null-safe Decimal helper: converts null to 0.
     *
     * @param d Decimal input
     * @return Decimal (never null)
     */
    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    // =========================
    // Child replace
    // =========================

    /**
     * @description replaceChildren
     * Replaces ALL child records for an invoice:
     *  - Deletes existing Invoice_Line__c, Invoice_Material__c, Invoice_Not_Included__c
     *  - Inserts new rows from payload
     *
     * @param invoiceId Parent Invoice__c Id
     * @param p         Payload containing sections/materials/not included
     */
    private static void replaceChildren(Id invoiceId, PayloadDTO p) {
        delete [SELECT Id FROM Invoice_Line__c WHERE Invoice__c = :invoiceId];
        delete [SELECT Id FROM Invoice_Material__c WHERE Invoice__c = :invoiceId];
        delete [SELECT Id FROM Invoice_Not_Included__c WHERE Invoice__c = :invoiceId];

        List<Invoice_Line__c> outLines = new List<Invoice_Line__c>();
        Integer sortNo = 1;

        for (SectionDTO s : p.sections) {

            // Section Type stored as picklist value
            String stPick  = String.isBlank(s.sectionType) ? DEFAULT_SECTION_TYPE : s.sectionType;
            String stCanon = canonType(stPick);

            // Section header row
            outLines.add(new Invoice_Line__c(
                Invoice__c      = invoiceId,
                Sort_Order__c   = sortNo++,
                Is_Section__c   = true,
                Section_Name__c = s.sectionName,
                Section_Type__c = stPick
            ));

            if (s.lines == null) {continue;}

            for (LineDTO l : s.lines) {
                Invoice_Line__c rec = new Invoice_Line__c();
                rec.Invoice__c = invoiceId;
                rec.Sort_Order__c = sortNo++;
                rec.Is_Section__c = false;

                rec.Section_Name__c = s.sectionName;
                rec.Section_Type__c = stPick;

                rec.Category__c = l.category;
                rec.Item__c = l.item;
                rec.Brand__c = l.brand;
                rec.Explanation__c = l.explanation;

                if (stCanon == 'WOOD') {
                    rec.L__c = l.l;
                    rec.H__c = l.h;
                    rec.Qty__c = l.qty;
                    rec.Rate__c = l.rate;

                    Decimal area = ((nz(l.l) * nz(l.h) * nz(l.qty)) / 144);
                    rec.Area_Sqft__c = area.setScale(2);
                    rec.Amount__c = (area * nz(l.rate)).setScale(2);
                }
                else if (stCanon == 'ELECTRICAL') {
                    String mode = String.isBlank(l.electricalMode) ? ELEC_MODE_QTY : l.electricalMode.trim().toUpperCase();
                    if (mode != ELEC_MODE_COILS && mode != ELEC_MODE_QTY) {mode = ELEC_MODE_QTY;}
                    rec.Electrical_Mode__c = mode;
                    rec.Rate__c = l.rate;

                    if (mode == ELEC_MODE_COILS) {
                        rec.Coils__c = l.coils;
                        rec.Meters__c = l.meters;
                        rec.Qty__c = null;
                        rec.Amount__c = (nz(l.meters) * nz(l.rate)).setScale(2);
                    } else {
                        rec.Coils__c = null;
                        rec.Meters__c = null;
                        rec.Qty__c = l.qty;
                        rec.Amount__c = (nz(l.qty) * nz(l.rate)).setScale(2);
                    }
                }
                else {
                    rec.Rate__c = null;
                    rec.L__c = null; rec.H__c = null; rec.Qty__c = null;
                    rec.Coils__c = null; rec.Meters__c = null; rec.Electrical_Mode__c = null;
                    rec.Area_Sqft__c = null;
                    rec.Amount__c = nz(l.amount).setScale(2);
                }

                outLines.add(rec);
            }
        }

        if (!outLines.isEmpty()) {insert outLines;}

        List<Invoice_Material__c> mats = new List<Invoice_Material__c>();
        Integer mc = 1;
        for (MaterialDTO m : p.materials) {
            mats.add(new Invoice_Material__c(
                Invoice__c = invoiceId,
                Sort_Order__c = (m.sortOrder != null ? m.sortOrder : mc++),
                Material__c = m.material,
                Brand__c = m.brand,
                Grade__c = m.grade
            ));
        }
        if (!mats.isEmpty()) {insert mats;}

        List<Invoice_Not_Included__c> ni = new List<Invoice_Not_Included__c>();
        Integer nc = 1;
        for (NotIncludedDTO n : p.notIncluded) {
            ni.add(new Invoice_Not_Included__c(
                Invoice__c = invoiceId,
                Sort_Order__c = (n.sortOrder != null ? n.sortOrder : nc++),
                Text__c = n.text
            ));
        }
        if (!ni.isEmpty()) {insert ni;}
    }

    // =========================
    // Helpers
    // =========================

    /**
     * @description findDraftOrLatestSubmitted
     * Returns:
     *  - latest Draft invoice for given Opportunity, if present
     *  - otherwise the latest Submitted invoice by CreatedDate
     *
     * @param oppId Opportunity Id
     * @return Invoice__c (Draft preferred) OR null
     */
    private static Invoice__c findDraftOrLatestSubmitted(Id oppId) {
        List<Invoice__c> drafts = [SELECT Id, Status__c, Version_No__c, Client_Name__c, Phone__c, Address__c,
                    Invoice_Date__c, Invoice_No__c, GST_Percent__c FROM Invoice__c
                    WHERE Opportunity__c = :oppId AND Status__c = :STATUS_DRAFT ORDER BY LastModifiedDate DESC LIMIT 1];
        if (!drafts.isEmpty()) {return drafts[0];}

        List<Invoice__c> latest = [SELECT Id, Status__c, Version_No__c, Client_Name__c, Phone__c, Address__c,
                    Invoice_Date__c, Invoice_No__c, GST_Percent__c FROM Invoice__c
                    WHERE Opportunity__c = :oppId AND Status__c = :STATUS_SUBMITTED ORDER BY CreatedDate DESC LIMIT 1];
        return latest.isEmpty() ? null : latest[0];
    }

    /**
     * @description getLatestSubmittedByCreated
     * Returns latest submitted invoice by CreatedDate.
     * Used to populate Previous_Invoice__c during submit.
     *
     * @param oppId Opportunity Id
     * @return Invoice__c or null
     */
    private static Invoice__c getLatestSubmittedByCreated(Id oppId) {
        List<Invoice__c> lst = [SELECT Id, Version_No__c FROM Invoice__c
                        WHERE Opportunity__c = :oppId AND Status__c = :STATUS_SUBMITTED
                        ORDER BY CreatedDate DESC LIMIT 1];
        return lst.isEmpty() ? null : lst[0];
    }

    /**
     * @description getNextVersionNumber
     * Computes the next Version_No__c for a new submission:
     *  - If MAX(Version_No__c) exists -> MAX + 1
     *  - Else use COUNT(submitted) + 1 (supports older data without versions)
     *
     * @param oppId Opportunity Id
     * @return next version number (>= 1)
     */
    private static Integer getNextVersionNumber(Id oppId) {
        AggregateResult ar = [SELECT MAX(Version_No__c) maxVer, COUNT(Id) cnt
            FROM Invoice__c WHERE Opportunity__c = :oppId AND Status__c = :STATUS_SUBMITTED];

        Decimal maxVer = (Decimal) ar.get('maxVer');
        Integer cnt = (Integer) ar.get('cnt');

        Integer base = (maxVer == null) ? cnt : maxVer.intValue();
        return base + 1;
    }

    /**
     * @description toSections
     * Converts database Invoice_Line__c rows (section rows + item rows)
     * into UI-friendly SectionDTO list.
     *
     * @param dbLines Invoice_Line__c rows ordered by Sort_Order__c
     * @return List<SectionDTO> for UI rendering
     */
    private static List<SectionDTO> toSections(List<Invoice_Line__c> dbLines) {
        List<SectionDTO> secs = new List<SectionDTO>();
        SectionDTO current;

        for (Invoice_Line__c dbLine : dbLines) {
            if (dbLine.Is_Section__c) {
                current = new SectionDTO();
                current.id = String.valueOf(dbLine.Id);
                current.sectionName = dbLine.Section_Name__c;
                current.sectionType = String.isBlank(dbLine.Section_Type__c) ? 'Other Works' : dbLine.Section_Type__c;
                current.lines = new List<LineDTO>();
                current.subtotal = 0;
                secs.add(current);
                continue;
            }
            if (current == null) {continue;}

            LineDTO dto = new LineDTO();
            dto.id = String.valueOf(dbLine.Id);
            dto.category = dbLine.Category__c;
            dto.item = dbLine.Item__c;
            dto.brand = dbLine.Brand__c;
            dto.explanation = dbLine.Explanation__c;

            dto.l = dbLine.L__c;
            dto.h = dbLine.H__c;
            dto.qty = dbLine.Qty__c;

            dto.electricalMode = dbLine.Electrical_Mode__c;
            dto.coils = dbLine.Coils__c;
            dto.meters = dbLine.Meters__c;

            dto.rate = dbLine.Rate__c;
            dto.amount = dbLine.Amount__c;

            current.lines.add(dto);
            current.subtotal += (dbLine.Amount__c == null ? 0 : dbLine.Amount__c);
        }

        for (SectionDTO s : secs) {
            s.subtotal = (s.subtotal == null ? 0 : s.subtotal).setScale(2);
        }
        return secs;
    }
}