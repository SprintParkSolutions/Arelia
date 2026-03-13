@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class AreliaPathController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllStages() {
        List<Map<String, String>> steps = new List<Map<String, String>>();
        
        // 1. Initial Stages
        steps.add(new Map<String, String>{ 'label' => 'Opportunity Created', 'value' => 'Opportunity Created' });
        steps.add(new Map<String, String>{ 'label' => 'Enter Architect Data', 'value' => 'Enter Architect Data' });
        steps.add(new Map<String, String>{ 'label' => 'Send Architecture Client Approval', 'value' => 'Send Architecture Client Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Client Architecture Approval', 'value' => 'Client Architecture Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Architecture Manager Approval', 'value' => 'Architecture Manager Approval' });
        
        // 2. Proforma Stages
        steps.add(new Map<String, String>{ 'label' => 'Upload Proforma Invoice', 'value' => 'Upload Proforma Invoice' });
        steps.add(new Map<String, String>{ 'label' => 'Proforma Client Approval', 'value' => 'Proforma Client Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Proforma Manager Approval', 'value' => 'Proforma Manager Approval' });
        
        // 3. Catalogue Stages (MOVED HERE)
        steps.add(new Map<String, String>{ 'label' => 'Catalogue Link Sent', 'value' => 'Catalogue Link Sent' });
        steps.add(new Map<String, String>{ 'label' => 'Catalogue Received', 'value' => 'Catalogue Received' });
        steps.add(new Map<String, String>{ 'label' => 'Catalogue Manager Approval', 'value' => 'Catalogue Manager Approval' });

        // 4. Budget & Payment Stages
        steps.add(new Map<String, String>{ 'label' => 'Budget Review Client Approval', 'value' => 'Budget Review Client Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Budget Review Manager Approval', 'value' => 'Budget Review Manager Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Payment Terms Manager Approval', 'value' => 'Payment Terms Manager Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Payment Terms Client Approval', 'value' => 'Payment Terms Client Approval' });

        // 5. Closing Stages
        steps.add(new Map<String, String>{ 'label' => 'Client Agreement Sent', 'value' => 'Client Agreement Sent' });
        steps.add(new Map<String, String>{ 'label' => 'Client Agreement Signed', 'value' => 'Client Agreement Signed' });
        steps.add(new Map<String, String>{ 'label' => 'Tender Invites', 'value' => 'Tender Invites' });
        steps.add(new Map<String, String>{ 'label' => 'Create Vendor Opps', 'value' => 'Create Vendor Opps' });
        steps.add(new Map<String, String>{ 'label' => 'Vendor Agreement Sent', 'value' => 'Vendor Agreement Sent' });
        steps.add(new Map<String, String>{ 'label' => 'Vendor Agreement Signed', 'value' => 'Vendor Agreement Signed' });
        steps.add(new Map<String, String>{ 'label' => 'Closed Won', 'value' => 'Closed Won' });

        // 6. Exceptions
        steps.add(new Map<String, String>{ 'label' => 'Negotiation/Review', 'value' => 'Negotiation/Review' });
        steps.add(new Map<String, String>{ 'label' => 'Resumed', 'value' => 'Resumed' });

        return steps;
    }

    @AuraEnabled(cacheable=true)
    public static String getPathStatus(Id oppId) {
        Opportunity opp = [SELECT Id, StageName, Architect_Name__c, 
                    Architecture_Client_Approval_Sent__c, Architecture_Manager_Approval__c,
                    Budget_Review_Status__c, Payment_Terms_Status__c, Catalogue_Link_Sent__c,
                    Client_Agreement_Sent__c, Client_Agreement_Signed__c, All_Vendors_Agreement_Completed__c, 
                    (SELECT Id, Vendor_Agreement_Sent__c FROM Vendor_Opportunities__r),
                    (SELECT Id FROM Architecture_Designs__r WHERE Status__c = 'Approved' LIMIT 1),
                    (SELECT Id, Status__c, Manager_Approval__c FROM Proforma_Invoices__r ORDER BY CreatedDate DESC LIMIT 1),
                    (SELECT Id, Manager_Approval__c FROM Quotations__r ORDER BY CreatedDate DESC LIMIT 1)
                FROM Opportunity WHERE Id = :oppId LIMIT 1];

        if (opp.StageName == 'Resumed') { return 'Resumed'; }
        if (opp.StageName == 'Negotiation/Review') { return 'Negotiation/Review'; }

        // 1. Initial
        String status = checkInitialStages(opp);
        if (status != null) { return status; }

        // 2. Proforma
        status = checkProformaStages(opp);
        if (status != null) { return status; }

        // 3. Catalogue (MOVED LOGIC HERE)
        // If Catalogue Link Sent is TRUE, we check these steps. 
        // If FALSE, we skip them (matching the UI hidden state).
        if (opp.Catalogue_Link_Sent__c == true) {
            status = checkCatalogueStages(opp);
            if (status != null) { return status; }
        }

        // 4. Budget & Payment (Logic continues here if Catalogue steps are done or skipped)
        status = checkBudgetAndPaymentStages(opp);
        if (status != null) { return status; }

        // 5. Closing
        status = checkAgreementStages(opp);
        if (status != null) { return status; }

        status = checkVendorAndClosingStages(opp);
        if (status != null) { return status; }

        return 'Closed Won';
    }

    // --- HELPER METHODS ---

    private static String checkInitialStages(Opportunity opp) {
        if (String.isBlank(opp.Architect_Name__c)) { return 'Enter Architect Data'; }
        if (opp.Architecture_Client_Approval_Sent__c == false) { return 'Send Architecture Client Approval'; }
        if (opp.Architecture_Designs__r == null || opp.Architecture_Designs__r.isEmpty()) { return 'Client Architecture Approval'; }
        if (opp.Architecture_Manager_Approval__c == false) { return 'Architecture Manager Approval'; }
        return null;
    }

    private static String checkProformaStages(Opportunity opp) {
        Proforma_Invoice__c inv = (opp.Proforma_Invoices__r != null && !opp.Proforma_Invoices__r.isEmpty()) 
                                  ? opp.Proforma_Invoices__r[0] : null;

        if (inv == null || inv.Status__c == 'Changes Requested' || inv.Status__c == 'Rejected') {
            return 'Upload Proforma Invoice';
        }
        if (inv.Status__c == 'Sent') {
            return 'Proforma Client Approval';
        }
        if (inv.Status__c == 'Approved') {
            if (inv.Manager_Approval__c != true) {
                return 'Proforma Manager Approval';
            }
            return null; 
        }
        return 'Upload Proforma Invoice';
    }

    private static String checkCatalogueStages(Opportunity opp) {
        if (opp.Quotations__r == null || opp.Quotations__r.isEmpty()) {
            return 'Catalogue Received';
        }
        if (opp.Quotations__r[0].Manager_Approval__c == false) {
            return 'Catalogue Manager Approval';
        }
        return null; 
    }

    private static String checkBudgetAndPaymentStages(Opportunity opp) {
        if (opp.Budget_Review_Status__c != 'Client Approved' && opp.Budget_Review_Status__c != 'Manager Approved') {
            return 'Budget Review Client Approval';
        }
        if (opp.Budget_Review_Status__c != 'Manager Approved') {
            return 'Budget Review Manager Approval';
        }
        if (opp.Payment_Terms_Status__c != 'Manager Approved' && opp.Payment_Terms_Status__c != 'Client Approved') {
            return 'Payment Terms Manager Approval';
        }
        if (opp.Payment_Terms_Status__c != 'Client Approved') {
            return 'Payment Terms Client Approval';
        }
        return null;
    }

    private static String checkAgreementStages(Opportunity opp) {
        if (opp.Client_Agreement_Sent__c == false) { return 'Client Agreement Sent'; }
        if (opp.Client_Agreement_Signed__c == false) { return 'Client Agreement Signed'; }
        return null;
    }

    private static String checkVendorAndClosingStages(Opportunity opp) {
        Boolean isVendorSent = false;
        if (opp.Vendor_Opportunities__r != null) {
            for (SObject vo : opp.Vendor_Opportunities__r) {
                if (vo.get('Vendor_Agreement_Sent__c') == true) {
                    isVendorSent = true;
                    break; 
                }
            }
        }
        
        if (isVendorSent == false) { return 'Tender Invites'; }
        if (opp.All_Vendors_Agreement_Completed__c == false) { return 'Vendor Agreement Signed'; }
        if (opp.StageName != 'Closed Won') { return 'Closed Won'; }
        return null;
    }
}