public without sharing class WhatsAppChatStore {

    public static void append(String e164OrDigits,
                              String direction,       // 'IN' | 'OUT'
                              String text,
                              String messageId,
                              String status,          // e.g., "delivered", "sent"
                              String mediaType,       // null or "image"/"application"/"video"/"audio"/"sticker"
                              Id contentDocumentId,
                              String externalUrl) {

        // Normalize & resolve an eligible lead (Lead.Id != null AND Lead.Project_Request_Quotation_Type__c != null).
        String digits = normalizeDigits(e164OrDigits);
        Lead lead = resolveEligibleLead(digits);
        if (lead == null) {
            // No eligible lead -> do nothing
            return;
        }

        // Guard: Only create/update when there is REAL chat content.
        // We treat "content" as:
        //   - non-blank text, OR
        //   - a media type, OR
        //   - an attached ContentDocument, OR
        //   - an external URL (e.g., image/file link)
        // Optionally also require a messageId (skip delivery/read status webhooks)
        if (!hasRealChatContent(text, mediaType, contentDocumentId, externalUrl) || String.isBlank(messageId)) {
            return;
        }

        // Get existing chat or claim an orphan by phone tail; if none, only now create.
        WhatsApp_Chat__c chat = findOrClaimChatForEligibleLead(lead, digits);
        if (chat == null) {
            chat = new WhatsApp_Chat__c();
            chat.Lead__c = lead.Id;
            chat.Message_Count__c = 0;
            chat.Transcript_NDJSON__c = '';
            insert chat;
        }

        // Build one NDJSON line
        Map<String,Object> line = new Map<String,Object>();
        line.put('ts', Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        line.put('dir', String.isBlank(direction) ? 'OUT' : direction);
        line.put('text', text);
        line.put('status', status);
        line.put('mediaType', mediaType);
        String e164 = e164OrDigits;
        line.put('fromNumber', 'OUT'.equalsIgnoreCase(direction) ? null : e164);
        line.put('toNumber',   'OUT'.equalsIgnoreCase(direction) ? e164 : null);
        line.put('contentDocumentId', contentDocumentId);
        line.put('externalUrl', externalUrl);
        line.put('messageId', messageId);

        String ndjson = JSON.serialize(line);

        // Append to rolling transcript (max ~100k chars kept)
        String current = chat.Transcript_NDJSON__c;
        if (current == null) current = '';
        if (current != '') {
            Integer clen = current.length();
            String lastChar = (clen > 0) ? current.substring(clen - 1, clen) : '';
            if (lastChar != '\n') current += '\n';
        }

        Integer MAX_KEEP = 100000;
        Integer extra = current.length() + ndjson.length() + 1 - MAX_KEEP;
        if (extra > 0) current = current.substring(Math.max(0, current.length() - extra));

        chat.Transcript_NDJSON__c = current + ndjson + '\n';
        chat.Last_Message_Time__c = System.now();
        if ('IN'.equalsIgnoreCase(direction)) { chat.Last_From__c = digits; chat.Last_To__c = null; }
        else                                  { chat.Last_From__c = null;   chat.Last_To__c = digits; }
        chat.Last_Status__c = status;
        chat.Message_Count__c = (chat.Message_Count__c == null ? 0 : chat.Message_Count__c) + 1;

        update chat;
    }

    /**
     * IMPORTANT CHANGE:
     * - This now only RETURNS an existing chat (or null).
     * - It never creates anything. So just opening a UI or checking won’t create records.
     */
    public static Id ensureChatFor(String e164OrDigits) {
        String digits = normalizeDigits(e164OrDigits);
        Lead lead = resolveEligibleLead(digits);
        if (lead == null) return null;

        WhatsApp_Chat__c chat = findExistingChatByLeadOrTail(lead.Id, digits);
        return chat == null ? null : chat.Id;
    }

    // ---- helpers ----
    private static Boolean hasRealChatContent(String text, String mediaType, Id contentDocumentId, String externalUrl) {
        if (!String.isBlank(text)) return true;
        if (!String.isBlank(mediaType)) return true;
        if (contentDocumentId != null) return true;
        if (!String.isBlank(externalUrl)) return true;
        return false;
    }

    private static String normalizeDigits(String e164OrDigits) {
        String d = (e164OrDigits == null) ? '' : e164OrDigits.replaceAll('[^0-9]', '');
        if (d.length() > 10) d = d.substring(d.length() - 10);
        return d;
    }

    // Return eligible lead only if Project_Request_Quotation_Type__c is populated
    private static Lead resolveEligibleLead(String last10) {
        if (String.isBlank(last10)) return null;
        List<Lead> leads = [
            SELECT Id, Project_Request_Quotation_Type__c
            FROM Lead
            WHERE (Phone LIKE :('%' + last10) OR MobilePhone LIKE :('%' + last10))
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (leads.isEmpty()) return null;
        Lead l = leads[0];
        return (l.Project_Request_Quotation_Type__c == null) ? null : l;
    }

    // Find existing chat linked to lead, else by phone tail (no creation)
    private static WhatsApp_Chat__c findExistingChatByLeadOrTail(Id leadId, String last10) {
        List<WhatsApp_Chat__c> byLead = [
            SELECT Id, Transcript_NDJSON__c, Message_Count__c, Last_Message_Time__c,
                   Last_From__c, Last_To__c, Last_Status__c, Lead__c
            FROM WhatsApp_Chat__c
            WHERE Lead__c = :leadId
            ORDER BY Last_Message_Time__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        if (!byLead.isEmpty()) return byLead[0];

        if (!String.isBlank(last10)) {
            List<WhatsApp_Chat__c> byTail = [
                SELECT Id, Transcript_NDJSON__c, Message_Count__c, Last_Message_Time__c,
                       Last_From__c, Last_To__c, Last_Status__c, Lead__c
                FROM WhatsApp_Chat__c
                WHERE (Last_From__c LIKE :('%' + last10) OR Last_To__c LIKE :('%' + last10))
                ORDER BY Last_Message_Time__c DESC, CreatedDate DESC
                LIMIT 1
            ];
            if (!byTail.isEmpty()) return byTail[0];
        }
        return null;
    }

    // Claim orphan (Lead__c = null) by tail for this eligible lead; if none, return null (do not create)
    private static WhatsApp_Chat__c findOrClaimChatForEligibleLead(Lead eligibleLead, String last10) {
        // Prefer existing by lead
        List<WhatsApp_Chat__c> byLead = [
            SELECT Id, Transcript_NDJSON__c, Message_Count__c, Last_Message_Time__c,
                   Last_From__c, Last_To__c, Last_Status__c, Lead__c
            FROM WhatsApp_Chat__c
            WHERE Lead__c = :eligibleLead.Id
            ORDER BY Last_Message_Time__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        if (!byLead.isEmpty()) return byLead[0];

        // Try to claim one orphan by tail
        if (!String.isBlank(last10)) {
            List<WhatsApp_Chat__c> orphanByTail = [
                SELECT Id, Transcript_NDJSON__c, Message_Count__c, Last_Message_Time__c,
                       Last_From__c, Last_To__c, Last_Status__c, Lead__c
                FROM WhatsApp_Chat__c
                WHERE Lead__c = null
                  AND (Last_From__c LIKE :('%' + last10) OR Last_To__c LIKE :('%' + last10))
                ORDER BY Last_Message_Time__c DESC, CreatedDate DESC
                LIMIT 1
            ];
            if (!orphanByTail.isEmpty()) {
                WhatsApp_Chat__c claimed = orphanByTail[0];
                claimed.Lead__c = eligibleLead.Id;
                update claimed;
                return claimed;
            }
        }

        // No existing/no orphan -> let caller decide to create (append does create; ensureChatFor does not)
        return null;
    }
}