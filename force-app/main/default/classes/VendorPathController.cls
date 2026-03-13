@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class VendorPathController {
    
    @AuraEnabled(cacheable=true)
    public static String getPathStatus(Id recordId) {
        // 1. Return null if no ID (same as Project Code)
        if (recordId == null) {
            return null;
        }

        // 2. Direct Query (Matches Project Code structure)
        // If this is an Account ID, this query simply returns 0 rows (Safe)
        List<Vendor_Assignment__c> vaList = [SELECT Id, Status__c 
                FROM Vendor_Assignment__c WHERE Id = :recordId LIMIT 1];
        
        // If empty, it means wrong object OR no access
        if (vaList.isEmpty()) {
            return null; 
        }

        Vendor_Assignment__c va = vaList[0];
        String status = va.Status__c;

        // 3. Logic to Determine the "Active Step"
        // Remember: Returning a step makes the PREVIOUS steps Green.

        // If Status is Completed -> "Vendor Work Completed" (Step 5) turns Green.
        // We handle this by returning the name itself, and handling the "Won" logic in JS/CSS.
        if (status == 'Completed') {
            return 'Vendor Work Completed';
        }
        
        if (status == 'Abscond') {
            return 'Abscond';
        }
        
        // If In Progress -> "Vendor Work Started" (Step 2) is Completed (Green).
        // Current Active Step becomes "Ongoing Tasks" (Step 3).
        if (status == 'In Progress' || status == 'In-Progress') {
            return 'Ongoing Tasks';
        }

        // If Initiated -> "Vendor Assigned" (Step 1) is Completed (Green).
        // Current Active Step becomes "Vendor Work Started" (Step 2).
        if (status == 'Initiated') {
            return 'Vendor Work Started';
        }

        // Default: Start at Step 1
        return 'Vendor Assigned';
    }
}