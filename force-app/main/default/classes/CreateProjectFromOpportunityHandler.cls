/* File: CreateProjectFromOpportunityHandler.cls
       @Description:
         When an Opportunity moves to Closed Won:
           - If a related Project__c (keyed by Project_Name__c = Opp.Id) exists → UPDATE it from Opp values
           - If not → CREATE it from Opp values and copy files from Opp to Project
     
         Gates (adds addError on the Opportunity row if any fail):
           - Client_Agreement_Signed__c = true
           - All_Vendors_Agreement_Completed__c = true
           - All Vendor_Opportunity__c.Vendor_Agreement_Signed__c = true
     
       Notes:
         - Bulk safe, low cognitive complexity, null-safe booleans.
         -Added CC of Sup and Enrollment team
    */
    @SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ApexUnitTestShouldNotUseSeeAllData')
    public with sharing class CreateProjectFromOpportunityHandler {
    
        // ---------- Orchestrator: AFTER INSERT (send customer email) ----------
        public static void handleAfterInsert(List<Opportunity> newList) {
            System.debug('CreateProjectFromOpportunityHandler.handleAfterInsert START, size=' +
                        (newList == null ? 0 : newList.size()));
    
            if (newList == null || newList.isEmpty()) {
                System.debug('Send email 23:: No opportunities in trigger; exiting.');
                return;
            }
    
            // Collect only Opps where Primary_Contact__c is populated
            Set<Id> oppIdsWithPrimaryContact = new Set<Id>();
            for (Opportunity o : newList) {
                if (o != null) {
                    oppIdsWithPrimaryContact.add(o.Id);
                }
            }
    
            // Query only fields required for email sending
            List<Opportunity> opps = [SELECT Id,
                    Email__c,
                    Primary_Contact__c,
                    Primary_Contact__r.Email,
                    Supervisor_User__c,
                    Supervisor_User__r.Email                  
                FROM Opportunity
                WHERE Id IN :oppIdsWithPrimaryContact
            ];
            System.debug('Send email 44::opps data::'+opps);
            if (opps.isEmpty()) {
                System.debug('Send email 45:: Query returned no opportunities; exiting.');
                return;
            }
    
            // Build emails
            List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    
            Id owdId = getDefaultOrgWideEmailAddressId();
            System.debug('OrgWideEmailAddress Id resolved as: ' + owdId);
    
            List<EmailTemplate> templateList = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = :Label.Arelia_Living_Architect_3D_Design_Approval_Email
                LIMIT 1
            ];
            if (templateList.isEmpty()) {
                System.debug('Send email 56:: No template found for DeveloperName = ' +
                            Label.Arelia_Living_Architect_3D_Design_Approval_Email);
                return;
            }
            Id templateId = templateList[0].Id;
    
            for (Opportunity oppData : opps) {

    if (oppData == null ||
        oppData.Primary_Contact__c == null ||
        oppData.Primary_Contact__r == null ||
        String.isBlank(oppData.Primary_Contact__r.Email)) {
        continue;
    }

    Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
    emailMessage.setTemplateId(templateId);

    // Required for template
    emailMessage.setTargetObjectId(oppData.Primary_Contact__c);
    emailMessage.setWhatId(oppData.Id);

    if (owdId != null) {
        emailMessage.setOrgWideEmailAddressId(owdId);
    }

    emailMessage.setSaveAsActivity(true);

    // ===============================
    // CC ADDRESSES (Supervisor + Label)
    // ===============================
    List<String> ccAddresses = new List<String>();

    // Supervisor Email
    if (oppData.Supervisor_User__r != null &&
        String.isNotBlank(oppData.Supervisor_User__r.Email)) {
        ccAddresses.add(oppData.Supervisor_User__r.Email.trim());
    }

    // Label Emails (comma or semicolon separated)
    String labelEmails = Label.Arelia_Living_Enrollment_Members;
    if (String.isNotBlank(labelEmails)) {
        for (String e : labelEmails.split('[,;]')) {
            if (String.isNotBlank(e)) {
                ccAddresses.add(e.trim());
            }
        }
    }

    // Remove duplicates
    ccAddresses = new List<String>(new Set<String>(ccAddresses));

    if (!ccAddresses.isEmpty()) {
        emailMessage.setCcAddresses(ccAddresses);
    }

    mails.add(emailMessage);
}
    
                
    
    
            try {
                System.debug('Send email 79:: Sending ' + mails.size() + ' email(s)...');
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(mails, false);
    
                for (Integer i = 0; i < results.size(); i++) {
                    Messaging.SendEmailResult r = results[i];
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            System.debug('Email ' + i + ' failed: ' + err.getStatusCode() +
                                        ' - ' + err.getMessage());
                        }
                    } else {
                        System.debug('Email ' + i + ' sent successfully.');
                    }
                }
            } catch (Exception e) {
                System.debug('Exception while sending emails: ' + e.getMessage());
            }
        }
    
    
         // ---------- Helper: Org-Wide Email Address from Custom Label ----------
        private static Id getDefaultOrgWideEmailAddressId() {
            List<OrgWideEmailAddress> owd = [SELECT Id FROM OrgWideEmailAddress
                WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
            return owd.isEmpty() ? null : owd[0].Id;
        }
    
        // ---------- Orchestrator: AFTER UPDATE (existing behavior) ----------
        public static void handleAfterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
            if (newList == null || newList.isEmpty()) {return;}
    
                // ---------------------------------------------
            // NEW: Send email when Primary_Contact__c is set by Flow
            // (old value = null, new value != null)
            // ---------------------------------------------
            List<Opportunity> newlyGotPrimaryContact = new List<Opportunity>();
            for (Opportunity newOpp : newList) {
                if (newOpp == null) {
                    continue;
                }
                Opportunity oldOpp = oldMap.get(newOpp.Id);
                if (oldOpp != null &&
                    oldOpp.Primary_Contact__c == null &&
                    newOpp.Primary_Contact__c != null) {
    
                    newlyGotPrimaryContact.add(newOpp);
                }
            }
    
            // Reuse existing email logic
            if (!newlyGotPrimaryContact.isEmpty()) {
    
                handleAfterInsert(newlyGotPrimaryContact);
            }
     
            // 1) Only Opps that just moved to Closed Won
            List<Opportunity> justClosedWon = pickJustClosedWon(newList, oldMap);
            if (justClosedWon.isEmpty()) {return;}
     
            // 2) Load vendor links for those Opps (for validation)
            Set<Id> oppIds = collectIds(justClosedWon);
            Map<Id, List<Vendor_Opportunity__c>> vendorsByOpp = loadVendorLinks(oppIds);
     
            // 3) Validate gates; invalid rows receive addError and are excluded
            List<Opportunity> validOpps = validateAndFilter(justClosedWon, vendorsByOpp);
            if (validOpps.isEmpty()) {return;}
     
            // 4) Find existing projects keyed by Project_Name__c = Opportunity.Id
            Map<Id, Project__c> existingByOppId = loadExistingProjectsByOppId(collectIds(validOpps));
     
            // 5) Build create/update lists
            List<Project__c> toInsert = new List<Project__c>();
            List<Project__c> toUpdate = new List<Project__c>();
            for (Opportunity opp : validOpps) {
                Project__c existing = existingByOppId.get(opp.Id);
                if (existing == null) {
                    toInsert.add(buildProjectFromOpp(opp, null));
                } else {
                    toUpdate.add(buildProjectFromOpp(opp, existing.Id));
                }
            }
     
            // 6) DML (update first or insert first — order does not matter functionally)
            if (!toUpdate.isEmpty()) {update toUpdate;}
     
            Map<Id, Id> oppToNewProject = new Map<Id, Id>();
            if (!toInsert.isEmpty()) {
                insert toInsert;
                // Map inserted projects back to Opps for file copy
                for (Project__c p : toInsert) {
                    if (p.Project_Name__c != null) {oppToNewProject.put(p.Project_Name__c, p.Id);}
                }
            }
     
            // 7) Copy files only for newly created projects (unchanged behavior)
            if (!oppToNewProject.isEmpty()) {copyFilesFromOppToProject(oppToNewProject);}
        }
    
        // ---------- Step 1: find Opps that just moved to Closed Won ----------
        private static List<Opportunity> pickJustClosedWon(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
            List<Opportunity> result = new List<Opportunity>();
            for (Opportunity opp : newList) {
                Opportunity oldOpp = oldMap.get(opp.Id);
                Boolean nowClosedWon = 'Closed Won'.equals(opp.StageName);
                Boolean wasClosedWon = (oldOpp != null && 'Closed Won'.equals(oldOpp.StageName));
                if (nowClosedWon && !wasClosedWon) {
                    result.add(opp);
                }
            }
            return result;
        }
     
        private static Set<Id> collectIds(List<Opportunity> opps) {
            Set<Id> ids = new Set<Id>();
            for (Opportunity o : opps) {ids.add(o.Id);}
            return ids;
        }
     
        // ---------- Step 2: fetch vendors per Opp ----------
        private static Map<Id, List<Vendor_Opportunity__c>> loadVendorLinks(Set<Id> oppIds) {
            Map<Id, List<Vendor_Opportunity__c>> mapByOpp = new Map<Id, List<Vendor_Opportunity__c>>();
            if (oppIds == null || oppIds.isEmpty()) {return mapByOpp;}
     
            for (Vendor_Opportunity__c vo : [SELECT Id, Opportunity__c, Vendor__c, Vendor__r.Name,
                       Vendor_Agreement_Sent__c, Vendor_Agreement_Signed__c
                FROM Vendor_Opportunity__c WHERE Opportunity__c IN :oppIds])
            {
                List<Vendor_Opportunity__c> bucket = mapByOpp.get(vo.Opportunity__c);
                if (bucket == null) {
                    bucket = new List<Vendor_Opportunity__c>();
                    mapByOpp.put(vo.Opportunity__c, bucket);
                }
                bucket.add(vo);
            }
            return mapByOpp;
        }
     
        // ---------- Step 3: validations (addError on the Opportunity row) ----------
        private static List<Opportunity> validateAndFilter(
            List<Opportunity> candidates,
            Map<Id, List<Vendor_Opportunity__c>> vendorsByOpp
        ) {
            List<Opportunity> valids = new List<Opportunity>();
            for (Opportunity opp : candidates) {
                List<String> errs = new List<String>();
                validateClientAgreement(opp, errs);
                validateAllVendorsCompleted(opp, errs);
                validateVendorsSigned(opp, vendorsByOpp.get(opp.Id), errs);
     
                if (!errs.isEmpty()) {
                    opp.addError('Cannot create/update Project: ' + String.join(errs, ' '));
                } else {
                    valids.add(opp);
                }
            }
            return valids;
        }
     
        private static void validateClientAgreement(Opportunity opp, List<String> errs) {
            if (opp.Client_Agreement_Signed__c != true) {
                errs.add('Client Agreement is not signed on Opportunity.');
            }
        }
     
        private static void validateAllVendorsCompleted(Opportunity opp, List<String> errs) {
            if (opp.All_Vendors_Agreement_Completed__c != true) {
                errs.add('All Vendors Agreement not completed. Please check.');
            }
        }
     
        private static void validateVendorsSigned(Opportunity opp, List<Vendor_Opportunity__c> links, List<String> errs) {
            if (links == null || links.isEmpty()) {
                errs.add('No Vendor_Opportunity__c records linked to this Opportunity.');
                return;
            }
            List<String> missing = new List<String>();
            for (Vendor_Opportunity__c vo : links) {
                if (vo.Vendor_Agreement_Signed__c != true) {
                    String nameOrId = (vo.Vendor__r != null && String.isNotBlank(vo.Vendor__r.Name))
                        ? vo.Vendor__r.Name : (String) vo.Vendor__c;
                    missing.add(nameOrId);
                }
            }
            if (!missing.isEmpty()) {
                errs.add('These vendor(s) have not signed the agreement: ' + String.join(missing, ', ') + '.');
            }
        }
     
        // ---------- Step 4: load existing Projects keyed by Opp.Id ----------
        private static Map<Id, Project__c> loadExistingProjectsByOppId(Set<Id> oppIds) {
            Map<Id, Project__c> out = new Map<Id, Project__c>();
            if (oppIds == null || oppIds.isEmpty()) {return out;}
     
            for (Project__c p : [SELECT Id, Project_Name__c FROM Project__c WHERE Project_Name__c IN :oppIds]) {
                if (p.Project_Name__c != null){ out.put((Id) p.Project_Name__c, p);}
            }
            return out;
        }
     
        // ---------- Step 5: build a Project row for INSERT or UPDATE ----------
        // Pass existingId = null for INSERT, or existing Project Id for UPDATE
        private static Project__c buildProjectFromOpp(Opportunity opp, Id existingId) {
            // Re-visit override logic
            final Boolean isRevisitConfirmed =
                'Re-Visit'.equalsIgnoreCase(opp.Appointment_Status__c) &&
                (opp.Re_Visit_Appointmnet_Confirmation__c == true);
     
            final Date endDateVal = isRevisitConfirmed
                ? opp.Re_Visit_Site_Supervisor_Completion_Date__c
                : opp.Project_End_Date__c;
     
            final Decimal estBudgetVal = isRevisitConfirmed
                ? opp.Re_Visit_Site_Supervisor_Estimate_Budget__c
                : opp.Supervisor_Estimated_Budget__c;
     
            final String estimatedMonths = isRevisitConfirmed
                ? opp.ReVisit_Site_Estimated_Completion_Months__c
                : opp.Project_Estimated_Completion_Months__c;
     
            Project__c p = new Project__c(
                Id                              = existingId,          // null for insert; non-null for update
                Description__c                  = opp.Project_Description__c,
                Budget__c                       = opp.Budget__c,
                Status__c                       = 'Initiated',
                IDC_Company__c                  = opp.AccountId,
                Client__c                       = opp.Primary_Contact__c,
                Project_Name__c                 = opp.Id,              // key back to Opportunity
                Client_Email__c                 = opp.Email__c,
                Name                            = opp.Name,
                Client_Phone__c                 = opp.Lead_Phone__c,
                Supervisor_User__c              = opp.Supervisor_User__c,
                Type_Of_Project__c              = opp.Type_of_Project__c,
                Project_Scope__c                = opp.Project_Scope__c,
            //    End_Date__c                     = endDateVal,
                Supervisor_Estimated_Budget__c  = estBudgetVal,
                // 🔹 NEW FIELD MAPPINGS 🔹
                Project_Request_Quotation_Type__c = opp.Project_Request_Quotation_Type__c,
                Site_Location__c                  = opp.Site_Location__c,
                Site_Space__c                     = opp.Site_Space__c,
                Plan_Level__c                     = opp.Plan_Level__c,
                Estimated_Project_Duration__c= estimatedMonths,
                Estimated_Budget__c               = opp.Estimated_Budget__c,
                Interior_Project_Type__c        = opp.Interior_Project_Type__c,
                Interior_Category__c            = opp.Interior_Category__c
     
            );
            return p;
        }
     
        // ---------- Step 6: file copy (only for newly created Projects) ----------
        private static void copyFilesFromOppToProject(Map<Id, Id> oppToProject) {
            if (oppToProject == null || oppToProject.isEmpty()) {return;}
     
            List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :oppToProject.keySet()
            ]) {
                Id projectId = oppToProject.get(link.LinkedEntityId);
                if (projectId == null) {continue;}
     
                toInsert.add(new ContentDocumentLink(
                    ContentDocumentId = link.ContentDocumentId,
                    LinkedEntityId    = projectId,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                ));
            }
            if (!toInsert.isEmpty()) {insert toInsert;}
        }
    }