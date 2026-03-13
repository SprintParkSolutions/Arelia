/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-06-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public class FileVisibilityHandler {
    
    /**
     * Entry point for Architecture Design trigger logic
     */
    public static void handleArchitectureDesign(List<Architecture_Design__c> newList, Map<Id, Architecture_Design__c> oldMap) {
        Map<Id, Id> designToOppMap = new Map<Id, Id>();

        for (Architecture_Design__c ad : newList) {
            Architecture_Design__c oldAd = oldMap.get(ad.Id);
            
            // Logic: Manager Approval changed from false to true
            if (ad.Manager_Approval__c && !oldAd.Manager_Approval__c && ad.Opportunity__c != null) {
                designToOppMap.put(ad.Id, ad.Opportunity__c);
            }
        }

        if (!designToOppMap.isEmpty()) {
            shareFilesWithOpportunity(designToOppMap);
        }
    }

    /**
     * Shared logic to link files from source records to Opportunities
     */
    public static void shareFilesWithOpportunity(Map<Id, Id> recordToOppMap) {
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();

        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :recordToOppMap.keySet()
        ]) {
            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = cdl.ContentDocumentId,
                LinkedEntityId = recordToOppMap.get(cdl.LinkedEntityId),
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        if (!newLinks.isEmpty()) {
            Database.insert(newLinks, false);
        }
    }
}