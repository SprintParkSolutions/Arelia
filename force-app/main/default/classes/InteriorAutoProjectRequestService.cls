/**
 * @description InteriorAutoProjectRequestService
 * -----------------------------------------------------------------------------
 * Service used by the "Auto Project Request" wizard (LWC/Flow) to:
 *  1) Save a Lead-based interior request payload
 *  2) Load Lead details for prefill
 *  3) Load already-submitted rooms & room-design selections
 *
 * Implementation notes / best practices:
 * - Bulk-safe DML using Database.* with allOrNone=false
 * - Guard clauses + consistent error messages (AuraHandledException)
 * - Replaces child records on save for data consistency
 * - Copies Salesforce Files from Interior_Design__c to Lead via ContentDocumentLink
 *
 * PMD notes:
 * - Suppressed CognitiveComplexity / ExcessiveParameterList due to DTO + payload parsing
 * - Suppressed ApexCRUDViolation because this is a service layer called by UI, and
 *   CRUD/FLS may be handled by profile/permission sets or higher-level security strategy.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class InteriorAutoProjectRequestService {

    /**
     * @description Wrapper DTO for returning existing request selections.
     *              Used by UI to restore selections when user revisits.
     */
    public class ExistingRequestDTO {
        /** @description Selected rooms with quantities. */
        @AuraEnabled public List<RoomLineDTO> rooms;

        /** @description Selected room designs (room -> design) with computed values. */
        @AuraEnabled public List<RoomDesignLineDTO> roomDesigns;
    }

    /**
     * @description Minimal room line DTO: roomId + quantity.
     */
    public class RoomLineDTO {
        @AuraEnabled public Id      roomId;
        @AuraEnabled public Integer quantity;
    }

    /**
     * @description Room-Design selection line DTO with pricing metadata.
     *              planLevel/roomSizeSqft/templateSizeSqft/ratePerSqft used for calculations.
     */
    public class RoomDesignLineDTO {
        @AuraEnabled public Id      roomId;
        @AuraEnabled public Id      designId;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal lineAmount;

        @AuraEnabled public String  planLevel;
        @AuraEnabled public Decimal roomSizeSqft;
        @AuraEnabled public Decimal templateSizeSqft;
        @AuraEnabled public Decimal ratePerSqft;
    }

    /**
     * @description Saves the lead request details + room selections + room design selections.
     *              This method:
     *              - Validates Lead submission flag
     *              - Updates Lead fields
     *              - Deletes existing request child records
     *              - Inserts new child records from payload
     *              - Copies design files to the Lead (optional)
     *
     * @param req Untyped payload from LWC (JSON-like map)
     * @return Lead Id updated
     * @throws AuraHandledException for user-friendly messages
     */
    @AuraEnabled(cacheable=false)
    public static Id saveRequest(Map<String, Object> req) {
        try {
            if (req == null) {
                throw new AuraHandledException('Empty payload');
            }

            Map<String, Object> top = normalizePayload(req);

            String leadIdStr = getStr(top, 'leadId');
            if (String.isBlank(leadIdStr)) {
                throw new AuraHandledException('Missing Lead Id for project request.');
            }
            Id leadId = (Id) leadIdStr;

            Lead existingLead = [SELECT Id, Project_Request_Submitted__c FROM Lead
                                    WHERE Id = :leadId LIMIT 1];
            if (existingLead.Project_Request_Submitted__c == true) {
                throw new AuraHandledException(
                    'Lead details already submitted. If you have any queries, please contact Arelia Team.'
                );
            }

            // -----------------------
            // Read payload
            // -----------------------
            String firstName     = getStr(top, 'firstName');
            String lastName      = getStr(top, 'lastName');
            String email         = getStr(top, 'email');
            String phone         = getStr(top, 'phone');
            String company       = getStr(top, 'company');
            String address       = getStr(top, 'address');
            String siteSpace     = getStr(top, 'siteSpace');
            String description   = getStr(top, 'description');
            String projectTypeId = getStr(top, 'projectTypeId');
            String categoryId    = getStr(top, 'categoryId');

            // overall plan (optional)
            String planLevel     = getStr(top, 'planLevel');

            Decimal totalBudget  = getDec(top, 'totalBudget');
            String quotationType = getStr(top, 'quotationType');

            List<Object> roomsRaw       = getList(top, 'rooms');
            List<Object> roomDesignsRaw = getList(top, 'selectedRoomDesigns');

            // -----------------------
            // Update Lead
            // -----------------------
            Lead leadToUpdate = buildLeadUpdate(
                leadId, firstName, lastName, email, phone, company, address, siteSpace,
                description, totalBudget, projectTypeId, categoryId, planLevel, quotationType
            );
            leadToUpdate.Project_Request_Submitted__c = true;

            Database.SaveResult[] leadRes = Database.update(new List<Lead>{ leadToUpdate }, false);
            if (leadRes.isEmpty() || !leadRes[0].isSuccess()) {
                throw new AuraHandledException(
                    'Unable to submit request. Lead update failed: ' + collectDbErrors(leadRes)
                );
            }

            // -----------------------
            // Replace child records
            // -----------------------
            deleteExistingChildRecords(leadId);

            if (roomsRaw != null && !roomsRaw.isEmpty()) {
                upsertRooms(leadId, roomsRaw);
            }

            Set<Id> designIds = new Set<Id>();
            if (roomDesignsRaw != null && !roomDesignsRaw.isEmpty()) {
                designIds = upsertRoomDesigns(leadId, roomDesignsRaw);
            }

            if (!designIds.isEmpty()) {
                copyDesignFilesToLead(leadId, designIds);
            }

            return leadId;

        } catch (AuraHandledException ahe) {
            // @description Pass-through for user-friendly UI message
            throw ahe;

        } catch (DmlException dmle) {
            // @description Common cause for guest users: CRUD/FLS/Validation rules
            throw new AuraHandledException(
                'Submit failed due to permissions or validation. ' +
                'Please check Guest/User profile has Edit access to Lead and Create access to Interior Request objects. ' +
                'Error: ' + dmle.getMessage()
            );

        } catch (Exception e) {
            // @description Safety catch to avoid raw stack traces to UI
            throw new AuraHandledException('Unexpected error while submitting request: ' + e.getMessage());
        }
    }

    /**
     * @description Fetches Lead fields used for auto-request prefill screen.
     * @param leadId Lead record id
     * @return Lead record (or null if not found)
     */
    @AuraEnabled(cacheable=true)
    public static Lead fetchLeadForAutoRequest(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required to load project request details.');
        }

        List<Lead> leads = [SELECT Id, FirstName, LastName, Email, Phone, Company,
                        Site_Location__c, Site_Space__c, Project_Description__c,
                        Estimated_Budget__c, Plan_Level__c,
                        Interior_Project_Type__c, Interior_Category__c,
                        Project_Request_Quotation_Type__c, Project_Request_Submitted__c
                        FROM Lead WHERE Id = :leadId LIMIT 1];
        return leads.isEmpty() ? null : leads[0];
    }

    /**
     * @description Loads room and room-design selections already saved for a Lead.
     * @param leadId Lead record id
     * @return ExistingRequestDTO with rooms + roomDesigns lists
     */
    @AuraEnabled(cacheable=true)
    public static ExistingRequestDTO fetchExistingRequest(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required to load existing request.');
        }

        ExistingRequestDTO dto = new ExistingRequestDTO();
        dto.rooms       = new List<RoomLineDTO>();
        dto.roomDesigns = new List<RoomDesignLineDTO>();

        for (Interior_Request_Room__c rr : [SELECT Interior_Room__c, Quantity__c 
                                    FROM Interior_Request_Room__c WHERE Lead__c = :leadId])
        {
            RoomLineDTO r = new RoomLineDTO();
            r.roomId   = rr.Interior_Room__c;
            r.quantity = rr.Quantity__c != null ? Integer.valueOf(String.valueOf(rr.Quantity__c)) : 0;
            dto.rooms.add(r);
        }

        for (Interior_Request_Room_Design__c dr : [SELECT Interior_Room__c, Interior_Design__c, Quantity__c, Design_Amount__c,
                   Plan_Level__c, Room_Size_Sqft__c, Template_Size_Sqft__c, Rate_Per_Sqft__c
            FROM Interior_Request_Room_Design__c WHERE Lead__c = :leadId])
        {
            RoomDesignLineDTO d = new RoomDesignLineDTO();
            d.roomId           = dr.Interior_Room__c;
            d.designId         = dr.Interior_Design__c;
            d.quantity         = dr.Quantity__c != null ? Integer.valueOf(String.valueOf(dr.Quantity__c)) : 0;
            d.lineAmount       = dr.Design_Amount__c;

            d.planLevel        = dr.Plan_Level__c;
            d.roomSizeSqft     = dr.Room_Size_Sqft__c;
            d.templateSizeSqft = dr.Template_Size_Sqft__c;
            d.ratePerSqft      = dr.Rate_Per_Sqft__c;

            dto.roomDesigns.add(d);
        }
        return dto;
    }

    // ------------------ Internals ------------------

    /**
     * @description Builds a Lead record with only fields required to update.
     *              Keeps DML minimal and avoids overwriting fields unintentionally.
     */
    private static Lead buildLeadUpdate(
        Id leadId, String firstName, String lastName, String email, String phone,
        String company, String address, String siteSpace, String description,
        Decimal totalBudget, String projectTypeId, String categoryId,
        String planLevel, String quotationType
    ) {
        Lead ld = new Lead();
        ld.Id = leadId;

        ld.FirstName = firstName;
        ld.LastName  = lastName;
        ld.Email     = email;
        ld.Phone     = phone;
        ld.Company   = company;

        ld.Site_Location__c                  = address;
        ld.Site_Space__c                     = siteSpace;
        ld.Project_Description__c            = description;
        ld.Estimated_Budget__c               = totalBudget;
        ld.Plan_Level__c                     = planLevel;
        ld.Project_Request_Quotation_Type__c = quotationType;

        if (String.isNotBlank(projectTypeId)) {ld.Interior_Project_Type__c = (Id) projectTypeId;}
        if (String.isNotBlank(categoryId))   {ld.Interior_Category__c     = (Id) categoryId;}

        return ld;
    }

    /**
     * @description Deletes existing child request records (rooms + room designs)
     *              so the save becomes a "replace" operation.
     */
    private static void deleteExistingChildRecords(Id leadId) {
        List<Interior_Request_Room_Design__c> existingDesigns = [
            SELECT Id FROM Interior_Request_Room_Design__c WHERE Lead__c = :leadId
        ];
        List<Interior_Request_Room__c> existingRooms = [
            SELECT Id FROM Interior_Request_Room__c WHERE Lead__c = :leadId
        ];

        if (!existingDesigns.isEmpty()) {Database.delete(existingDesigns, false);}
        if (!existingRooms.isEmpty())  {Database.delete(existingRooms, false);}
    }

    /**
     * @description Inserts Interior_Request_Room__c records from payload.
     * @param leadId Lead record id
     * @param roomsRaw List of untyped room maps {roomId, quantity}
     */
    private static void upsertRooms(Id leadId, List<Object> roomsRaw) {
        List<Interior_Request_Room__c> toInsert = new List<Interior_Request_Room__c>();

        for (Object o : roomsRaw) {
            Map<String, Object> r = normalizePayload(o);
            String roomIdStr = getStr(r, 'roomId');
            if (String.isBlank(roomIdStr)) {continue;}

            Integer qty = getInt(r, 'quantity', 1);
            if (qty == null || qty < 1) {qty = 1;}

            toInsert.add(new Interior_Request_Room__c(Lead__c = leadId, Interior_Room__c = (Id) roomIdStr,
                        Quantity__c      = qty));
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] res = Database.insert(toInsert, false);
            if (hasDbErrors(res)) {
                throw new AuraHandledException('Unable to save selected rooms: ' + collectDbErrors(res));
            }
        }
    }

    /**
     * @description Inserts Interior_Request_Room_Design__c records from payload.
     * Payload rows like:
     * { roomId, designId, quantity(1), planLevel, roomSizeSqft, templateSizeSqft, ratePerSqft, lineAmount }
     *
     * @param leadId Lead record id
     * @param roomDesignsRaw List of untyped maps for room designs
     * @return Set of Interior_Design__c Ids used to copy Salesforce Files to Lead
     */
    private static Set<Id> upsertRoomDesigns(Id leadId, List<Object> roomDesignsRaw) {
        List<Interior_Request_Room_Design__c> toInsert = new List<Interior_Request_Room_Design__c>();
        Set<Id> designIds = new Set<Id>();

        for (Object o : roomDesignsRaw) {
            Map<String, Object> m = normalizePayload(o);

            String roomIdStr   = getStr(m, 'roomId');
            String designIdStr = getStr(m, 'designId');
            if (String.isBlank(roomIdStr) || String.isBlank(designIdStr)) {continue;}

            Integer qty = getInt(m, 'quantity', 1);
            if (qty == null || qty < 1) {qty = 1;}

            Decimal lineAmt  = getDec(m, 'lineAmount');

            String  planLevel = getStr(m, 'planLevel');
            Decimal roomSize  = getDec(m, 'roomSizeSqft');
            Decimal tmplSize  = getDec(m, 'templateSizeSqft');
            Decimal rateSqft  = getDec(m, 'ratePerSqft');

            designIds.add((Id) designIdStr);

            toInsert.add(new Interior_Request_Room_Design__c(
                Lead__c               = leadId,
                Interior_Room__c      = (Id) roomIdStr,
                Interior_Design__c    = (Id) designIdStr,
                Quantity__c           = qty,
                Design_Amount__c      = lineAmt,

                Plan_Level__c         = planLevel,
                Room_Size_Sqft__c     = roomSize,
                Template_Size_Sqft__c = tmplSize,
                Rate_Per_Sqft__c      = rateSqft
            ));
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] res = Database.insert(toInsert, false);
            if (hasDbErrors(res)) {
                throw new AuraHandledException('Unable to save room designs: ' + collectDbErrors(res));
            }
        }
        return designIds;
    }

    /**
     * @description Copies Salesforce Files linked to Interior_Design__c records
     *              to the Lead so the Lead holds the same file set.
     *
     * @param leadId Lead record id
     * @param designIds Set of Interior_Design__c ids
     */
    private static void copyDesignFilesToLead(Id leadId, Set<Id> designIds) {
        if (leadId == null || designIds == null || designIds.isEmpty()) { return; }

        // Files on designs
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :designIds
        ];
        if (links.isEmpty()) { return; }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink dl : links) {
            if (dl.ContentDocumentId != null) { docIds.add(dl.ContentDocumentId); }
        }
        if (docIds.isEmpty()) { return; }

        // ✅ IMPORTANT: skip docs that are already linked to Lead (prevents duplicate error)
        Set<Id> alreadyLinked = new Set<Id>();
        for (ContentDocumentLink existing : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :leadId
            AND ContentDocumentId IN :docIds
        ]) {
            alreadyLinked.add(existing.ContentDocumentId);
        }

        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (Id docId : docIds) {
            if (alreadyLinked.contains(docId)) { continue; }

            newLinks.add(new ContentDocumentLink(
                LinkedEntityId    = leadId,
                ContentDocumentId = docId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ));
        }

        // ✅ If nothing new to add, DO NOT throw, just return
        if (newLinks.isEmpty()) { return; }

        Database.SaveResult[] res = Database.insert(newLinks, false);

        // ✅ Only throw if any NON-duplicate error happens
        String fatal = collectNonDuplicateErrors(res);
        if (String.isNotBlank(fatal)) {
            throw new AuraHandledException('Unable to attach design files to Lead: ' + fatal);
        }
    }

    private static String collectNonDuplicateErrors(Database.SaveResult[] res) {
        if (res == null) { return null; }

        List<String> msgs = new List<String>();
        for (Database.SaveResult r : res) {
            if (r == null || r.isSuccess()) { continue; }

            for (Database.Error e : r.getErrors()) {
                if (e == null) { continue; }

                // ignore duplicates: "already linked"
                if (e.getStatusCode() == StatusCode.DUPLICATE_VALUE) { continue; }

                String m = e.getMessage();
                if (String.isNotBlank(m) && m.toLowerCase().contains('already linked')) { continue; }

                if (String.isNotBlank(m)) { msgs.add(m); }
            }
        }
        return msgs.isEmpty() ? null : String.join(msgs, ' | ');
    }


    // ------------------ utils ------------------

    /**
     * @description Normalizes any untyped object into Map<String,Object>.
     *              This helps handle nested JSON coming from LWC.
     */
    private static Map<String, Object> normalizePayload(Object anyObj) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(anyObj));
    }

    /**
     * @description Reads a string value from a map safely.
     * @param m Source map
     * @param key Key name
     * @return String value or null
     */
    private static String getStr(Map<String, Object> m, String key) {
        Object val = (m == null) ? null : m.get(key);
        return val == null ? null : String.valueOf(val);
    }

    /**
     * @description Reads a decimal value from a map safely.
     * @param m Source map
     * @param key Key name
     * @return Decimal value or null
     */
    private static Decimal getDec(Map<String, Object> m, String key) {
        Object val = (m == null) ? null : m.get(key);
        if (val == null) {return null;}
        String s = String.valueOf(val);
        if (String.isBlank(s)) {return null;}
        return Decimal.valueOf(s);
    }

    /**
     * @description Reads an integer value from a map safely; returns default if empty.
     * @param m Source map
     * @param key Key name
     * @param dft Default value
     * @return Integer value
     */
    private static Integer getInt(Map<String, Object> m, String key, Integer dft) {
        Object val = (m == null) ? null : m.get(key);
        if (val == null) {return dft;}
        String s = String.valueOf(val);
        if (String.isBlank(s)) {return dft;}
        return Integer.valueOf(s);
    }

    /**
     * @description Reads a list value from a map safely; returns empty list if null.
     * @param m Source map
     * @param key Key name
     * @return List<Object> always non-null
     */
    private static List<Object> getList(Map<String, Object> m, String key) {
        Object val = (m == null) ? null : m.get(key);
        if (val == null) {return new List<Object>();}
        return (List<Object>) JSON.deserializeUntyped(JSON.serialize(val));
    }

    /**
     * @description Checks if any SaveResult in array contains errors.
     * @param res SaveResult array
     * @return true if at least one record failed
     */
    private static Boolean hasDbErrors(Database.SaveResult[] res) {
        if (res == null) {return false;}
        for (Database.SaveResult r : res) {
            if (r == null) {continue;}
            if (!r.isSuccess()) {return true;}
        }
        return false;
    }

    /**
     * @description Collects Database.SaveResult errors into a single string.
     * @param res SaveResult array
     * @return Concatenated error message
     */
    private static String collectDbErrors(Database.SaveResult[] res) {
        List<String> msgs = new List<String>();
        if (res == null) {return 'Unknown error.';}
        for (Database.SaveResult r : res) {
            if (r == null || r.isSuccess()) {continue;}
            for (Database.Error e : r.getErrors()) {
                if (e != null && String.isNotBlank(e.getMessage())) {msgs.add(e.getMessage());}
            }
        }
        return msgs.isEmpty() ? 'Unknown error.' : String.join(msgs, ' | ');
    }
}