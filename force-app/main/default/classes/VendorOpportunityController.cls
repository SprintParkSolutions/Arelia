/**
 * @description       : Controller for Vendor Opportunity handling
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-28-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class VendorOpportunityController {

    /**
     * @description Wrapper class to send Field Set data to LWC
     */
    public class FieldSetMember {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldPath;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean isEditable;
    }

    /**
    * @description Fetches fields from a given FieldSet on an object
    * @param objectName The API name of the object
    * @param fieldSetName The API name of the FieldSet
    * @return List<FieldSetMember> List of fields in the FieldSet
    */
    @AuraEnabled(cacheable=true)
    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    public static List<FieldSetMember> getFieldSetFields(String objectName, String fieldSetName) {
        List<FieldSetMember> fieldList = new List<FieldSetMember>();
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);

        if (sObjectType == null) {
            return fieldList;
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Schema.FieldSet fieldSet = describeResult.fieldSets.getMap().get(fieldSetName);

        if (fieldSet != null) {
            for (Schema.FieldSetMember f : fieldSet.getFields()) {
                FieldSetMember wrapper = new FieldSetMember();
                wrapper.label = f.getLabel();
                wrapper.fieldPath = f.getFieldPath();
                wrapper.required = f.getRequired() || f.getDbRequired();
                fieldList.add(wrapper);
            }
        }
        return fieldList;
    }

    /**
    * @description Checks if any Vendor Opportunity records exist for the Opportunity
    * @param opportunityId The ID of the parent Opportunity
    * @return Boolean True if records exist
    */
    @AuraEnabled
    public static Boolean hasExistingRecords(Id opportunityId) {
        // Manual CRUD Check for Legacy API Compatibility
        if (!Schema.sObjectType.Vendor_Opportunity__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to access Vendor Opportunity.');
        }
        
        Integer count = [SELECT Count() FROM Vendor_Opportunity__c WHERE Opportunity__c = :opportunityId];
        return count > 0;
    }

    /**
    * @description Creates Vendor Opportunity records linked to the Opportunity
    * @param records List of Vendor_Opportunity__c records to insert
    * @param opportunityId The ID of the parent Opportunity
    * @return List<Vendor_Opportunity__c> The created records
    */
    @AuraEnabled
    public static List<Vendor_Opportunity__c> createVendorOpportunities(List<Vendor_Opportunity__c> records, Id opportunityId) {
        // Manual Create Check
        if (!Schema.sObjectType.Vendor_Opportunity__c.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Vendor Opportunity.');
        }

        for(Vendor_Opportunity__c vo : records) {
            vo.Opportunity__c = opportunityId; // Hard-code link for security
        }

        insert records;
        return records;
    }

    /**
    * @description Retrieves existing Vendor Opportunity records
    * @param opportunityId The ID of the parent Opportunity
    * @param queryFields List of field API names to query
    * @return List<Vendor_Opportunity__c> List of queried records
    */
    @AuraEnabled
    public static List<Vendor_Opportunity__c> getExistingRecords(Id opportunityId, List<String> queryFields) {
        // Manual Access Check
        if (!Schema.sObjectType.Vendor_Opportunity__c.isAccessible()) {
             throw new AuraHandledException('Insufficient permissions to read Vendor Opportunity.');
        }

        if(!queryFields.contains('Id')) {
            queryFields.add('Id');
        }

        // Escape single quotes to prevent SOQL injection
        String fields = String.escapeSingleQuotes(String.join(queryFields, ','));

        String query = 'SELECT ' + fields +
                       ' FROM Vendor_Opportunity__c WHERE Opportunity__c = :opportunityId';

        return Database.query(query);
    }

    /**
    * @description Reparents files to the new Vendor Opportunity records
    * @param fileMap Map of ContentDocumentId to LinkedEntityId
    */
    @AuraEnabled
    public static void reparentFiles(Map<String, String> fileMap) {
        // Manual Create Check
        if (!Schema.sObjectType.ContentDocumentLink.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to share files.');
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();

        // Loop through the map: Key = DocId, Value = VendorOpportunityId
        for(String docId : fileMap.keySet()) {
            ContentDocumentLink newLink = new ContentDocumentLink();
            newLink.ContentDocumentId = docId; // The file
            newLink.LinkedEntityId = fileMap.get(docId); // The new Vendor Opportunity
            newLink.ShareType = 'V'; // 'V' = Viewer
            linksToInsert.add(newLink);
        }

        if(!linksToInsert.isEmpty()) {
            insert linksToInsert;
        }
    }

    /**
    * @description Retrieves file names for a list of parent record IDs
    * @param parentIds List of parent record IDs
    * @return Map<Id, String> Map of ParentId to File Name
    */
    @AuraEnabled
    public static Map<Id, String> getAttachedFileNames(List<Id> parentIds) {
        // Manual Access Check
        if (!Schema.sObjectType.ContentDocumentLink.isAccessible()) {
             return new Map<Id, String>(); // Fail gracefully if no access
        }

        Map<Id, String> fileMap = new Map<Id, String>();

        // Query without WITH SECURITY_ENFORCED (Manual check performed above)
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :parentIds
            ORDER BY SystemModstamp DESC
        ];

        // Map Parent ID to File Name (taking the most recent one if multiple exist)
        for(ContentDocumentLink link : links) {
            if(!fileMap.containsKey(link.LinkedEntityId)) {
                fileMap.put(link.LinkedEntityId, link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension);
            }
        }
        return fileMap;
    }
}