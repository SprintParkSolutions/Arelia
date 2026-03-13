public without sharing class WhatsAppChatRelinker {

    /**
     * Call from Lead after-update.
     * For any Lead that just flipped IsConverted false -> true,
     * copy ConvertedOpportunityId / ConvertedAccountId / ConvertedContactId
     * into related WhatsApp_Chat__c rows.
     */
    public static void onAfterUpdate(List<Lead> newList, Map<Id, Lead> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        // 1) Collect just-converted leads
        Map<Id, Lead> justConverted = new Map<Id, Lead>();
        for (Lead l : newList) {
            Lead oldL = oldMap.get(l.Id);
            if (l.IsConverted && (oldL == null || !oldL.IsConverted)) {
                justConverted.put(l.Id, l);
            }
        }
        if (justConverted.isEmpty()) return;

        // 2) Find chats still attached to those leads
        List<WhatsApp_Chat__c> chats = [
            SELECT Id, Lead__c, Opportunity__c
            FROM WhatsApp_Chat__c
            WHERE Lead__c IN :justConverted.keySet()
        ];
        if (chats.isEmpty()) return;

        // 3) Populate new lookups (don’t overwrite if already set)
        List<WhatsApp_Chat__c> toUpdate = new List<WhatsApp_Chat__c>();
        for (WhatsApp_Chat__c c : chats) {
            Lead src = justConverted.get(c.Lead__c);
            if (src == null) continue;

            Boolean changed = false;
            if (c.Opportunity__c == null && src.ConvertedOpportunityId != null) {
                c.Opportunity__c = src.ConvertedOpportunityId; changed = true;
            }
            if (changed) toUpdate.add(c);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}