public without sharing class WhatsAppController {

    public class ChatLine {
        @AuraEnabled public String   id;
        @AuraEnabled public Datetime ts;
        @AuraEnabled public String   dir;
        @AuraEnabled public String   text;
        @AuraEnabled public String   fromNumber;
        @AuraEnabled public String   toNumber;
        @AuraEnabled public String   status;
        @AuraEnabled public String   mediaType;
        @AuraEnabled public Id       contentDocumentId;
        @AuraEnabled public String   externalUrl;
        @AuraEnabled public String   messageId;   // used for de-dupe
    }
    private class ChatLineCmp implements System.Comparator<ChatLine> {
        public Integer compare(ChatLine a, ChatLine b) {
            Datetime ta = (a == null || a.ts == null) ? Datetime.newInstance(1900,1,1) : a.ts;
            Datetime tb = (b == null || b.ts == null) ? Datetime.newInstance(1900,1,1) : b.ts;
            if (ta == tb) return 0; return (ta < tb) ? -1 : 1;
        }
    }

    public class FileRow {
        @AuraEnabled public Id    contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String ext;
        @AuraEnabled public Boolean hasPublic;
        @AuraEnabled public String publicUrl;
    }

    // -------- Lead page ----------
    @AuraEnabled(cacheable=false)
    public static List<ChatLine> getUnifiedChat(Id leadId, Integer limitCount) {
        if (leadId == null) return new List<ChatLine>();
        Integer keep = (limitCount == null || limitCount <= 0) ? 300 : limitCount;

        List<ChatLine> out = new List<ChatLine>();
        Set<Id> seenChatIds = new Set<Id>();

        for (WhatsApp_Chat__c c : [
            SELECT Id, Transcript_NDJSON__c, Last_Message_Time__c
            FROM WhatsApp_Chat__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ]) {
            if (!seenChatIds.add(c.Id)) continue;
            addFromTranscript(c.Transcript_NDJSON__c, out, c.Id);
        }

        String last10 = tail10OfLead(leadId);
        if (!String.isBlank(last10)) {
            for (WhatsApp_Chat__c c2 : [
                SELECT Id, Transcript_NDJSON__c, Last_Message_Time__c, Lead__c
                FROM WhatsApp_Chat__c
                WHERE Lead__c = null
                  AND (Last_From__c LIKE :('%' + last10) OR Last_To__c LIKE :('%' + last10))
                ORDER BY CreatedDate ASC
                LIMIT 3
            ]) {
                if (!seenChatIds.add(c2.Id)) continue;
                addFromTranscript(c2.Transcript_NDJSON__c, out, c2.Id);
            }
        }

        out = dedupeLines(out);
        out.sort(new ChatLineCmp());

        // ---- manual trim (no subList) ----
        if (out.size() > keep) {
            Integer start = Math.max(0, out.size() - keep);
            List<ChatLine> trimmed = new List<ChatLine>();
            for (Integer i = start; i < out.size(); i++) trimmed.add(out[i]);
            out = trimmed;
        }
        return out;
    }

    // -------- Opportunity page ----------
    @AuraEnabled(cacheable=false)
    public static List<ChatLine> getUnifiedChatForOpportunity(Id opportunityId, Integer limitCount) {
        if (opportunityId == null) return new List<ChatLine>();
        Integer keep = (limitCount == null || limitCount <= 0) ? 300 : limitCount;

        List<ChatLine> out = new List<ChatLine>();
        Set<Id> seenChatIds = new Set<Id>();

        for (WhatsApp_Chat__c c : [
            SELECT Id, Transcript_NDJSON__c, Last_Message_Time__c
            FROM WhatsApp_Chat__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ]) {
            if (!seenChatIds.add(c.Id)) continue;
            addFromTranscript(c.Transcript_NDJSON__c, out, c.Id);
        }

        List<Lead> src = [
            SELECT Id
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!src.isEmpty()) out.addAll(getUnifiedChat(src[0].Id, keep));

        out = dedupeLines(out);
        out.sort(new ChatLineCmp());

        // ---- manual trim (no subList) ----
        if (out.size() > keep) {
            Integer start = Math.max(0, out.size() - keep);
            List<ChatLine> trimmed = new List<ChatLine>();
            for (Integer i = start; i < out.size(); i++) trimmed.add(out[i]);
            out = trimmed;
        }
        return out;
    }

    // -------- other public endpoints --------
    @AuraEnabled(cacheable=false)
    public static Id ensureChatForNumber(String e164OrDigits) {
        if (String.isBlank(e164OrDigits)) return null;
        return WhatsAppChatStore.ensureChatFor(e164OrDigits);
    }

    @AuraEnabled(cacheable=false)
    public static List<FileRow> getFilesForChat(Id chatId) {
        if (chatId == null) return new List<FileRow>();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :chatId
        ];
        if (links.isEmpty()) return new List<FileRow>();

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) docIds.add(l.ContentDocumentId);

        List<ContentVersion> cvs = [
            SELECT Id, ContentDocumentId, Title, FileExtension, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
        ];
        Map<Id, ContentVersion> docIdToCv = new Map<Id, ContentVersion>();
        Set<Id> cvIds = new Set<Id>();
        for (ContentVersion cv : cvs) { docIdToCv.put(cv.ContentDocumentId, cv); cvIds.add(cv.Id); }

        Map<Id, ContentDistribution> cvIdToCd = new Map<Id, ContentDistribution>();
        if (!cvIds.isEmpty()) {
            for (ContentDistribution cd : [
                SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution
                WHERE ContentVersionId IN :cvIds
            ]) if (!cvIdToCd.containsKey(cd.ContentVersionId)) cvIdToCd.put(cd.ContentVersionId, cd);
        }

        List<FileRow> out = new List<FileRow>();
        for (Id docId : docIds) {
            ContentVersion cv = docIdToCv.get(docId);
            if (cv == null) continue;
            ContentDistribution cd = cvIdToCd.get(cv.Id);

            FileRow fr = new FileRow();
            fr.contentDocumentId = docId;
            fr.title = cv.Title;
            fr.ext   = cv.FileExtension;
            fr.hasPublic = (cd != null) && (!String.isBlank(cd.ContentDownloadUrl) || !String.isBlank(cd.DistributionPublicUrl));
            fr.publicUrl = (cd != null && !String.isBlank(cd.ContentDownloadUrl)) ? cd.ContentDownloadUrl :
                           (cd != null ? cd.DistributionPublicUrl : null);
            out.add(fr);
        }
        return out;
    }

    @AuraEnabled(cacheable=false)
    public static String makePublicLink(Id contentDocumentId) {
        return WhatsAppMediaService.ensurePublicLink(contentDocumentId);
    }

    @AuraEnabled(cacheable=false)
    public static WhatsAppService.SendResult makePublicAndSend(Id contentDocumentId, String toE164, String caption) {
        return WhatsAppService.sendMediaFromDocument(contentDocumentId, toE164, caption);
    }

    // -------- helpers --------
    private static void addFromTranscript(String blobText, List<ChatLine> bucket, Id recordId) {
        if (String.isBlank(blobText)) return;
        Integer seq = 0;
        for (String obj : extractJsonObjects(blobText)) {
            try {
                Object o = JSON.deserializeUntyped(obj);
                if (o instanceof Map<String, Object>) {
                    ChatLine cl = fromMap((Map<String, Object>)o);
                    cl.id = String.valueOf(recordId) + ':' + String.valueOf(seq++);
                    bucket.add(cl);
                }
            } catch (Exception ignoreOne) {}
        }
    }
    private static List<String> extractJsonObjects(String s) {
        List<String> out = new List<String>();
        if (String.isBlank(s)) return out;
        Integer n = s.length();
        Boolean inString = false, esc = false;
        Integer depth = 0, start = -1;
        for (Integer i = 0; i < n; i++) {
            String ch = s.substring(i, i+1);
            if (start < 0) { if (ch == '{') { start = i; depth = 1; inString = false; esc = false; } continue; }
            if (esc) { esc = false; continue; }
            if (ch == '\\') { if (inString) esc = true; continue; }
            if (ch == '"') { inString = !inString; continue; }
            if (!inString) {
                if (ch == '{') depth++;
                else if (ch == '}') { depth--; if (depth == 0) { out.add(s.substring(start, i+1)); start = -1; } }
            }
        }
        return out;
    }
    private static ChatLine fromMap(Map<String, Object> m) {
        ChatLine cl = new ChatLine();
        cl.text       = (String) m.get('text');
        cl.dir        = (String) m.get('dir');
        if (String.isBlank(cl.dir)) {
            String fn = (String) m.get('fromNumber'), tn = (String) m.get('toNumber');
            cl.dir = (fn != null && fn != '') ? 'IN' : 'OUT';
            if (tn != null && tn != '' && fn == null) cl.dir = 'OUT';
        }
        cl.status     = (String) m.get('status');
        cl.mediaType  = (String) m.get('mediaType');
        cl.fromNumber = (String) m.get('fromNumber');
        cl.toNumber   = (String) m.get('toNumber');
        cl.messageId  = (String) m.get('messageId');

        String iso = (String) m.get('ts');
        if (iso != null) {
            try {
                String dt = iso.replace('T', ' ').replace('Z', '');
                cl.ts = Datetime.valueOfGmt(dt);
            } catch (Exception e) { cl.ts = System.now(); }
        } else { cl.ts = System.now(); }

        Object cdoc = m.get('contentDocumentId');
        if (cdoc != null) { try { cl.contentDocumentId = (Id) cdoc; } catch (Exception ignore) {} }
        cl.externalUrl = (String) m.get('externalUrl');
        return cl;
    }
    private static String tail10OfLead(Id leadId) {
        if (leadId == null) return null;
        Lead l = [SELECT Phone, MobilePhone FROM Lead WHERE Id = :leadId LIMIT 1];
        String raw = (l.MobilePhone != null && l.MobilePhone != '') ? l.MobilePhone : l.Phone;
        if (raw == null) return null;
        String digits = raw.replaceAll('[^0-9]', '');
        return (digits.length() > 10) ? digits.substring(digits.length() - 10) : digits;
    }
    private static List<ChatLine> dedupeLines(List<ChatLine> lines) {
        Map<String, ChatLine> uniq = new Map<String, ChatLine>();
        for (ChatLine cl : lines) {
            String k = cl.messageId;
            if (String.isBlank(k)) {
                Datetime t = (cl.ts == null) ? Datetime.newInstance(1900,1,1) : cl.ts;
                k = t.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') + '|' +
                    (cl.dir == null ? '' : cl.dir) + '|' +
                    (cl.text == null ? '' : cl.text) + '|' +
                    (cl.fromNumber == null ? '' : cl.fromNumber) + '|' +
                    (cl.toNumber == null ? '' : cl.toNumber);
            }
            if (!uniq.containsKey(k)) uniq.put(k, cl);
        }
        return new List<ChatLine>(uniq.values());
    }

    // ADD to WhatsAppController

    @AuraEnabled(cacheable=false)
    public static List<ChatLine> getUnifiedChatForProject(Id projectId, Integer limitCount) {
        if (projectId == null) return new List<ChatLine>();
        Integer keep = (limitCount == null || limitCount <= 0) ? 300 : limitCount;

        List<ChatLine> out = new List<ChatLine>();
        Set<Id> seenChatIds = new Set<Id>();

        for (WhatsApp_Chat__c c : [
            SELECT Id, Transcript_NDJSON__c
            FROM WhatsApp_Chat__c
            WHERE Project__c = :projectId
            ORDER BY CreatedDate ASC
            LIMIT 1000
        ]) { if (seenChatIds.add(c.Id)) addFromTranscript(c.Transcript_NDJSON__c, out, c.Id); }

        // (Optional) also pull via the Project's Opportunity
        Project__c p = [SELECT Project_Name__c FROM Project__c WHERE Id = :projectId LIMIT 1];
        if (p.Project_Name__c != null) out.addAll(getUnifiedChatForOpportunity(p.Project_Name__c, keep));

        out = dedupeLines(out);
        out.sort(new ChatLineCmp());
        if (out.size() > keep) {
            Integer start = Math.max(0, out.size() - keep);
            List<ChatLine> trimmed = new List<ChatLine>();
            for (Integer i = start; i < out.size(); i++) trimmed.add(out[i]);
            out = trimmed;
        }
        return out;
    }


}