/**
 * @description
 *  Controller used by InvoicePdf Visualforce page.
 *  Loads:
 *    - Invoice header data
 *    - Section + line items
 *    - Materials list
 *    - Not Included list
 *
 *  Data is grouped into SectionWrap for easier rendering in PDF.
 *
 *  Notes:
 *   - Read-only controller (no DML)
 *   - Handles invalid / missing Invoice Id safely
 *   - Keeps logic simple for PDF rendering
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class InvoicePdfController {

    public Invoice__c inv { get; private set; }
    public List<SectionWrap> sections { get; private set; }
    public List<Invoice_Material__c> materials { get; private set; }
    public List<Invoice_Not_Included__c> notIncluded { get; private set; }
    public String errorMessage { get; private set; }

    /**
     * Wrapper class to group section header + line rows
     */
    public class SectionWrap {
        public String sectionName { get; set; }
        public String sectionType { get; set; }   // picklist stored value
        public String typeKey     { get; set; }   // WOOD / ELECTRICAL / OTHER
        public List<Invoice_Line__c> rows { get; set; }

        public Boolean getIsWood()       { return typeKey == 'WOOD'; }
        public Boolean getIsElectrical() { return typeKey == 'ELECTRICAL'; }
        public Boolean getIsOther()      { return typeKey == 'OTHER'; }
    }

     /**
     * Converts raw section type into canonical type.
     * Ensures consistent behavior across:
     *  - LWC
     *  - InvoiceService
     *  - PDF rendering
     */
    private static String canonType(String raw) {
        if (String.isBlank(raw)) {return 'OTHER';}
        String u = raw.trim().toUpperCase();

        if (u == 'WOOD' || u.contains('WOOD')) {return 'WOOD';}
        if (u.contains('ELECTRIC')) {return 'ELECTRICAL';}
        if (u.contains('CIVIL')) {return 'WOOD';}     // civil behaves like wood
        if (u.contains('OTHER')) {return 'OTHER';}
        return 'OTHER';
    }

    /**
     * Constructor
     * Loads all required invoice data for PDF rendering.
     */
    public InvoicePdfController() {
        sections = new List<SectionWrap>();
        materials = new List<Invoice_Material__c>();
        notIncluded = new List<Invoice_Not_Included__c>();
        errorMessage = null;

        String invoiceIdStr = ApexPages.currentPage().getParameters().get('id');
        if (String.isBlank(invoiceIdStr)) {
            errorMessage = 'Invoice Id missing in URL.';
            inv = new Invoice__c();
            return;
        }

        Id invoiceId;
        try {
            invoiceId = (Id) invoiceIdStr;
        } catch (Exception e) {
            errorMessage = 'Invalid Invoice Id format.';
            inv = new Invoice__c();
            return;
        }

        List<Invoice__c> invList = [SELECT Id, Client_Name__c, Phone__c, Address__c,
                     Invoice_No__c, Invoice_Date__c, Version_No__c,
                    GST_Percent__c, Total__c, GST_Amount__c, Grand_Total__c
                    FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];
        if (invList.isEmpty()) {
            errorMessage = 'Invoice not found or no access.';
            inv = new Invoice__c();
            return;
        }
        inv = invList[0];

        List<Invoice_Line__c> allLines = [SELECT Is_Section__c, Section_Name__c, Section_Type__c,
                Category__c, Item__c, Brand__c, Explanation__c,
                L__c, H__c, Qty__c, Area_Sqft__c, Electrical_Mode__c, Coils__c, Meters__c,
                Rate__c, Amount__c, Sort_Order__c FROM Invoice_Line__c
                WHERE Invoice__c = :invoiceId ORDER BY Sort_Order__c];

        SectionWrap current;
        for (Invoice_Line__c l : allLines) {
            if (l.Is_Section__c) {
                current = new SectionWrap();
                current.sectionName = l.Section_Name__c;
                current.sectionType = String.isBlank(l.Section_Type__c) ? 'Other Works' : l.Section_Type__c;
                current.typeKey = canonType(current.sectionType);
                current.rows = new List<Invoice_Line__c>();
                sections.add(current);
            } else if (current != null) {
                current.rows.add(l);
            }
        }

        materials = [SELECT Material__c, Brand__c, Grade__c, Sort_Order__c
            FROM Invoice_Material__c WHERE Invoice__c = :invoiceId
            ORDER BY Sort_Order__c];

        notIncluded = [SELECT Text__c, Sort_Order__c FROM Invoice_Not_Included__c
            WHERE Invoice__c = :invoiceId ORDER BY Sort_Order__c];
    }
}