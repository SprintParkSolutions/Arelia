@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class SVRWizardController {

    /* ========== GET LATEST SVR (Strict Record Type Check) ========== */
    @AuraEnabled
    public static Site_Visit_Report__c getLatestSVR(Id parentId, String objectApiName) {
        if (parentId == null) {
            return null;
        }

        List<Site_Visit_Report__c> svrs = new List<Site_Visit_Report__c>();

        // FIX: Switched to Static SOQL to resolve "ApexSOQLInjection" PMD error
        if (objectApiName == 'Lead') {
            svrs = [
                SELECT Id, Wizard_Step__c, Is_Final_Submitted__c, Layout_Blueprint_Uploaded__c, Management_Approval__c
                FROM Site_Visit_Report__c
                WHERE RecordType.Name = 'Lead Site Visit Report'
                AND Lead__c = :parentId
               
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } else if (objectApiName == 'Opportunity') {
            svrs = [
                SELECT Id, Wizard_Step__c, Is_Final_Submitted__c, Layout_Blueprint_Uploaded__c, Management_Approval__c
                FROM Site_Visit_Report__c
                WHERE RecordType.Name = 'Opportunity Site Visit Report'
                AND Opportunity__c = :parentId
                
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }

        return svrs.isEmpty() ? null : svrs[0];
    }

    /* ========== CREATE SVR ========== */
    @AuraEnabled
    public static Id createSVR(Id parentId, String objectApiName, Site_Visit_Report__c draftData) {
        
        Site_Visit_Report__c existing = getLatestSVR(parentId, objectApiName);
        if (existing != null) {
            return existing.Id;
        }

        String rtName = '';
        if (objectApiName == 'Lead') {
            draftData.Lead__c = parentId;
            rtName = 'Lead Site Visit Report';
        } else if (objectApiName == 'Opportunity') {
            draftData.Opportunity__c = parentId;
            rtName = 'Opportunity Site Visit Report';
        }

        if (String.isNotBlank(rtName)) {
            try {
                draftData.RecordTypeId = Schema.SObjectType.Site_Visit_Report__c
                    .getRecordTypeInfosByName()
                    .get(rtName)
                    .getRecordTypeId();
            } catch (Exception e) {
                throw new AuraHandledException('Record Type "' + rtName + '" not found.');
            }
        }

        draftData.Wizard_Step__c = 2;

        try {
            
            Database.insert(draftData);
        } catch (DmlException e) {
            // Captures Validation Rule errors for the LWC
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        
        return draftData.Id;
    }

    /* ========== SAVE STEP ========== */
    @AuraEnabled
    public static void saveStep(Id svrId, Integer stepNo) {
        Site_Visit_Report__c toUpdate = new Site_Visit_Report__c(Id = svrId, Wizard_Step__c = stepNo);
        Database.update(toUpdate);
    }

    /* ========== SAVE DRAFT ========== */
    @AuraEnabled
    public static void saveDraft(Site_Visit_Report__c data) {
        try {
            Database.update(data);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /* ========== MARK BLUEPRINT ========== */
    @AuraEnabled
    public static void markBlueprintUploaded(Id svrId) {
        Site_Visit_Report__c toUpdate = new Site_Visit_Report__c(Id = svrId, Layout_Blueprint_Uploaded__c = true);
        Database.update(toUpdate);
    }

    /* ========== FINAL SUBMIT ========== */
    @AuraEnabled
    public static void finalSubmit(Id svrId) {
        Site_Visit_Report__c toUpdate = new Site_Visit_Report__c(
            Id = svrId,
            Wizard_Step__c = 3,
            Is_Final_Submitted__c = true,
            Site_Visit_Report_Status__c = 'Approved' 
        );
        Database.update(toUpdate);
    }

    /* ========== UTILS ========== */
    @AuraEnabled(cacheable=true)
    public static List<String> getFieldSetFields(String objectApi, String fieldSetName) {
        List<String> fields = new List<String>();
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApi);
        if (t == null) {
            return fields;
        }
        
        Schema.DescribeSObjectResult describe = t.getDescribe();
        if (describe.fieldSets.getMap().containsKey(fieldSetName)) {
            Schema.FieldSet fs = describe.fieldSets.getMap().get(fieldSetName);
            for (Schema.FieldSetMember f : fs.getFields()) {
                fields.add(f.getFieldPath());
            }
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContentDocumentLink> getFiles(Id recordId) {
        return [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            
        ];
    }
}