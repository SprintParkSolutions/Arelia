public without sharing class WhatsAppMediaService {

    public class SavedMedia {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String externalUrl;
        public SavedMedia(Id cdid, String url) { contentDocumentId = cdid; externalUrl = url; }
    }

    public static Map<String,Object> getMediaMeta(String mediaId) {
        if (String.isBlank(mediaId)) return null;
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(WhatsAppConfig.mediaMetaEndpoint(mediaId));
        req.setTimeout(120000);
        req.setHeader('Authorization', 'Bearer ' + WhatsAppConfig.accessToken());
        HTTP http = new HTTP();
        HTTPResponse res = http.send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return null;
        Object o = JSON.deserializeUntyped(res.getBody());
        return (o instanceof Map<String,Object>) ? (Map<String,Object>)o : null;
    }

    public static SavedMedia fetchAndSaveToChat(String mediaId, Id chatId, String preferredFilename) {
        Map<String,Object> meta = getMediaMeta(mediaId);
        if (meta == null) throw new AuraHandledException('Meta lookup failed for mediaId=' + mediaId);

        String url      = (String) meta.get('url');
        String mime     = (String) meta.get('mime_type');
        String fromMeta = (String) meta.get('filename');

        String filename = firstNonBlank(fromMeta, preferredFilename, 'whatsapp_file');
        String ext      = normalizeExtension(filename, mime);
        if (!filename.toLowerCase().endsWith('.' + ext)) filename += '.' + ext;

        HTTPResponse res = getWithRedirects(url, 3);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException('Media download failed ' + res.getStatusCode() + ' for ' + url);
        }

        ContentVersion cv = new ContentVersion();
        cv.Title        = stripExtension(filename);
        cv.PathOnClient = '/' + filename;
        cv.VersionData  = res.getBodyAsBlob();
        if (chatId != null) cv.FirstPublishLocationId = chatId;
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        if (chatId != null) {
            try {
                insert new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId    = chatId,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                );
            } catch (Exception ignore) {}
        }

        String publicUrl = null;
        try { publicUrl = ensurePublicLink(cv.ContentDocumentId); } catch (Exception ignore) {}
        return new SavedMedia(cv.ContentDocumentId, publicUrl);
    }

    private static HTTPResponse getWithRedirects(String startUrl, Integer maxHops) {
        HTTP http = new HTTP();
        Integer hops = 0;

        HTTPResponse res = http.send(makeGet(startUrl, true));
        System.debug(LoggingLevel.WARN, 'WA DL hop ' + hops + ' ' + res.getStatusCode() +
                     ' url=' + startUrl + ' next=' + res.getHeader('Location'));

        while (isRedirect(res) && hops < (maxHops == null ? 0 : maxHops)) {
            String loc = res.getHeader('Location');
            if (String.isBlank(loc)) break;
            hops++;
            Boolean needsAuth = (loc.contains('lookaside.whatsapp.net') || loc.contains('lookaside.fbsbx.com'));
            res = http.send(makeGet(loc, needsAuth));
            System.debug(LoggingLevel.WARN, 'WA DL hop ' + hops + ' ' + res.getStatusCode() +
                         ' url=' + loc + ' next=' + res.getHeader('Location'));
        }
        return res;
    }
    private static Boolean isRedirect(HTTPResponse res) {
        Integer sc = res.getStatusCode();
        return sc == 301 || sc == 302 || sc == 303 || sc == 307 || sc == 308;
    }
    private static HttpRequest makeGet(String url, Boolean includeAuth) {
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(url);
        req.setTimeout(120000);
        req.setCompressed(true);
        req.setHeader('Accept', '*/*');
        if (includeAuth == true) req.setHeader('Authorization', 'Bearer ' + WhatsAppConfig.accessToken());
        return req;
    }

    public static String ensurePublicLink(Id contentDocumentId) {
        if (contentDocumentId == null) return null;

        ContentVersion cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];

        List<ContentDistribution> existing = [
            SELECT Id, DistributionPublicUrl, ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            ContentDistribution ex = existing[0];
            if (!String.isBlank(ex.ContentDownloadUrl))    return ex.ContentDownloadUrl;
            if (!String.isBlank(ex.DistributionPublicUrl)) return ex.DistributionPublicUrl;
        }

        ContentDistribution cd = new ContentDistribution(
            Name                             = 'WhatsApp Public Link - ' + Datetime.now().getTime(),
            ContentVersionId                 = cv.Id,
            PreferencesAllowOriginalDownload = true,
            PreferencesPasswordRequired      = false,
            PreferencesNotifyOnVisit         = false,
            PreferencesLinkLatestVersion     = true
        );
        insert cd;

        if (!String.isBlank(cd.ContentDownloadUrl))    return cd.ContentDownloadUrl;
        return cd.DistributionPublicUrl;
    }

    // utils
    private static String firstNonBlank(String a, String b, String c) {
        if (!String.isBlank(a)) return a;
        if (!String.isBlank(b)) return b;
        return c;
    }
    private static String stripExtension(String name) {
        if (String.isBlank(name)) return 'file';
        Integer p = name.lastIndexOf('.');
        return (p > 0) ? name.substring(0, p) : name;
    }
    private static String normalizeExtension(String filename, String mime) {
        String lower = (filename == null ? '' : filename.toLowerCase());
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return lower.endsWith('.jpeg') ? 'jpeg' : 'jpg';
        if (lower.endsWith('.png'))  return 'png';
        if (lower.endsWith('.gif'))  return 'gif';
        if (lower.endsWith('.webp')) return 'webp';
        if (lower.endsWith('.mp4'))  return 'mp4';
        if (lower.endsWith('.3gp'))  return '3gp';
        if (lower.endsWith('.mp3'))  return 'mp3';
        if (lower.endsWith('.m4a'))  return 'm4a';
        if (lower.endsWith('.ogg'))  return 'ogg';
        if (lower.endsWith('.pdf'))  return 'pdf';

        if (mime == null) return 'bin';
        String m = mime.toLowerCase();
        if (m.contains('jpeg')) return 'jpg';
        if (m.contains('png'))  return 'png';
        if (m.contains('gif'))  return 'gif';
        if (m.contains('webp')) return 'webp';
        if (m.contains('mp4'))  return 'mp4';
        if (m.contains('3gpp')) return '3gp';
        if (m.contains('pdf'))  return 'pdf';
        if (m.contains('mp3'))  return 'mp3';
        if (m.contains('m4a'))  return 'm4a';
        if (m.contains('ogg'))  return 'ogg';
        return 'bin';
    }
}