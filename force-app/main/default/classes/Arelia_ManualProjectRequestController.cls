/**
 * @FileName    : Arelia_ManualProjectRequestController.cls
 * @description : Backend logic for manual project request screen.
 *                - Returns Lead data
 *                - Returns dynamic picklist values
 *                - Updates Lead with project info and quotation type
 */

@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
 public without sharing class Arelia_ManualProjectRequestController {

    /**
     * @description Returns a Lead by Id for pre-populating the form.
     *              If leadId is null, simply returns null (no error).
     */
    @AuraEnabled(cacheable=true)
    public static Lead getLeadById(Id leadId) {
        if (leadId == null) {
            return null;
        }

        if (!Schema.sObjectType.Lead.isAccessible()) {
            throw new AuraHandledException('You do not have permission to access Lead records.');
        }

        List<Lead> leads = [
            SELECT Id,
                   FirstName,
                   LastName,
                   Email,
                   Phone,
                   Company,
                   Customer_Budget__c,
                   Type_Of_Project__c,
                   Project_Scope__c,
                   Plan_Level__c,                  // 🔹 NEW
                   Project_Description__c,
                   Site_Location__c,
                   Project_Request_Quotation_Type__c,
                   Project_Request_Submitted__c,
                   Site_Space__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        return leads.isEmpty() ? null : leads[0];
    }

    /**
     * @description Returns picklist labels for Lead.Type_Of_Project__c dynamically.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getTypeOfProjectPicklistValues() {
        List<String> values = new List<String>();

        Schema.DescribeFieldResult describeResult = Lead.Type_Of_Project__c.getDescribe();
        for (Schema.PicklistEntry pe : describeResult.getPicklistValues()) {
            values.add(pe.getLabel());
        }

        return values;
    }

    /**
     * @description Returns picklist labels for Lead.Plan_Level__c dynamically.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getPlanLevelPicklistValues() {
        List<String> values = new List<String>();

        Schema.DescribeFieldResult describeResult = Lead.Plan_Level__c.getDescribe();
        for (Schema.PicklistEntry pe : describeResult.getPicklistValues()) {
            values.add(pe.getLabel());
        }

        return values;
    }

    /**
     * @description Updates the Lead with manual project request information.
     *              Uses a payload map to avoid ExcessiveParameterList PMD rule.
     *              Also prevents second submission using Project_Request_Submitted__c.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    @AuraEnabled
    public static void updateLead(Map<String, Object> payload) {
        // No payload / no lead – nothing to do (fail silently for UI)
        if (payload == null || !payload.containsKey('leadId') || payload.get('leadId') == null) {
            return;
        }

        Id leadId = (Id) payload.get('leadId');

        // ---- Load Lead including Project_Request_Submitted__c ----
        List<Lead> leads = [
            SELECT Id,
                   Project_Request_Submitted__c,
                   FirstName,
                   LastName,
                   Email,
                   Phone,
                   Company,
                   Customer_Budget__c,
                   Type_Of_Project__c,
                   Project_Scope__c,
                   Plan_Level__c,                  // 🔹 NEW
                   Site_Space__c,
                   Project_Description__c,
                   Site_Location__c,
                   Project_Request_Quotation_Type__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            // Lead not found – nothing to update, avoid throwing a hard error
            return;
        }

        Lead existingLead = leads[0];

        // ---- prevent second submission ----
        if (existingLead.Project_Request_Submitted__c == true) {
            throw new AuraHandledException(
                'Lead details already submitted. If you have any queries, please contact Arelia Team.'
            );
        }

        // ---- Update fields from payload ----
        existingLead.FirstName              = (String) payload.get('firstName');
        existingLead.LastName               = (String) payload.get('lastName');
        existingLead.Email                  = (String) payload.get('email');
        existingLead.Phone                  = (String) payload.get('phone');
        existingLead.Type_Of_Project__c     = (String) payload.get('typeOfProject');
        existingLead.Project_Scope__c       = (String) payload.get('projectScope');
        existingLead.Plan_Level__c          = (String) payload.get('planLevel'); // 🔹 NEW
        existingLead.Company                = (String) payload.get('company');
        existingLead.Project_Description__c = (String) payload.get('projectDescription');
        existingLead.Site_Location__c       = (String) payload.get('siteLocation');
        existingLead.Project_Request_Quotation_Type__c =
            (String) payload.get('quotationType');

        // Budget (Decimal)
        if (payload.containsKey('budget') && payload.get('budget') != null) {
            existingLead.Customer_Budget__c = (Decimal) payload.get('budget');
        } else {
            existingLead.Customer_Budget__c = null;
        }

        // Site Space (TEXT field)
        if (payload.containsKey('siteSpace') && payload.get('siteSpace') != null) {
            existingLead.Site_Space__c = (String) payload.get('siteSpace');
        } else {
            existingLead.Site_Space__c = null;
        }

        // Mark as submitted
        existingLead.Project_Request_Submitted__c = true;

        update existingLead;
    }
}