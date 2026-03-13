/**
 * @description       : Unit tests for InteriorAutoProjectRequestService.
 *                      Extra coverage added for:
 *                      - lead update failure branch (collectDbErrors path)
 *                      - copyDesignFilesToLead() "already linked" skip path (newLinks.isEmpty() return)
 *                      - payload skip/continue branches + quantity normalization
 *
 * @group             : Arelia Living
 */
@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ApexAssertionsShouldIncludeMessage')
private class InteriorAutoProjectRequestServiceTest {

    /* =========================================================
       TEST DATA SETUP
       ========================================================= */
    @TestSetup
    static void setupData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User testUser = new User(
            Alias = 'stdusr',
            Email = 'standarduser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'standarduser' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        System.runAs(testUser) {
            // Lead
            Lead ld = TestDataUtility.createLead('AutoRequest Test');
            ld.Email = 'test@example.com';
            ld.Phone = '555-555-5555';
            ld.Project_Request_Submitted__c = false;
            update ld;

            // Master data
            Interior_Room__c room = new Interior_Room__c(Name = 'Living Room');
            insert room;

            Interior_Design__c design = new Interior_Design__c(Name = 'Luxury Design');
            insert design;

            // Existing request records (to cover deleteExistingChildRecords)
            insert new Interior_Request_Room__c(
                Lead__c = ld.Id,
                Interior_Room__c = room.Id,
                Quantity__c = 1
            );

            insert new Interior_Request_Room_Design__c(
                Lead__c = ld.Id,
                Interior_Room__c = room.Id,
                Interior_Design__c = design.Id,
                Quantity__c = 1,
                Design_Amount__c = 100
            );

            // File linked to DESIGN
            ContentVersion cv = TestDataUtility.createContentVersion('Design Spec', 'Test File Content Data');
            TestDataUtility.linkFileToRecord(cv.Id, design.Id);
        }
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
    }

    private static Lead getLead() {
        return [SELECT Id, LastName, Company, Project_Request_Submitted__c FROM Lead LIMIT 1];
    }

    private static Interior_Room__c getRoom() {
        return [SELECT Id FROM Interior_Room__c LIMIT 1];
    }

    private static Interior_Design__c getDesign() {
        return [SELECT Id FROM Interior_Design__c LIMIT 1];
    }

    /* =========================================================
       TESTS: SAVE REQUEST
       ========================================================= */

    @IsTest
    static void testSaveRequestHappyPath() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = getLead();
            Interior_Room__c room = getRoom();
            Interior_Design__c design = getDesign();

            Integer leadFileCountBefore =
                [SELECT Count() FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id];

            List<Object> rooms = new List<Object>{
                new Map<String, Object>{ 'roomId' => room.Id, 'quantity' => 5 }
            };

            List<Object> designs = new List<Object>{
                new Map<String, Object>{
                    'roomId' => room.Id,
                    'designId' => design.Id,
                    'quantity' => 2,
                    'lineAmount' => 5000.50,
                    'planLevel' => 'Standard',
                    'roomSizeSqft' => 100,
                    'templateSizeSqft' => 80,
                    'ratePerSqft' => 50
                }
            };

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'firstName' => 'John',
                'lastName' => 'Doe',
                'email' => 'john.doe@test.com',
                'phone' => '1234567890',
                'company' => 'JD Corp',
                'address' => '123 Main St',
                'siteSpace' => '2 BHK',
                'description' => 'Full Reno',
                'totalBudget' => 50000,
                'planLevel' => 'Standard',
                'quotationType' => 'Manual',
                'projectTypeId' => null,
                'categoryId' => null,
                'rooms' => rooms,
                'selectedRoomDesigns' => designs
            };

            Test.startTest();
            Id resultId = InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            Lead updatedLead = [
                SELECT FirstName, LastName, Project_Request_Submitted__c, Estimated_Budget__c
                FROM Lead
                WHERE Id = :resultId
            ];
            System.assertEquals('John', updatedLead.FirstName);
            System.assertEquals('Doe', updatedLead.LastName);
            System.assertEquals(50000, updatedLead.Estimated_Budget__c);
            System.assertEquals(true, updatedLead.Project_Request_Submitted__c);

            List<Interior_Request_Room__c> newRooms =
                [SELECT Quantity__c FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
            System.assertEquals(1, newRooms.size());
            System.assertEquals(5, newRooms[0].Quantity__c);

            List<Interior_Request_Room_Design__c> newDesigns =
                [SELECT Design_Amount__c, Quantity__c FROM Interior_Request_Room_Design__c WHERE Lead__c = :ld.Id];
            System.assertEquals(1, newDesigns.size());
            System.assertEquals(5000.50, newDesigns[0].Design_Amount__c);
            System.assertEquals(2, newDesigns[0].Quantity__c);

            Integer leadFileCountAfter =
                [SELECT Count() FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id];
            System.assert(leadFileCountAfter > leadFileCountBefore);
        }
    }

    /**
     * Covers:
     * - qty defaulting (missing quantity)
     * - qty normalization (<1 becomes 1)
     * - skip branch (blank roomId)
     * - skip branch (room design missing designId)
     */
    @IsTest
    static void testSaveRequestWithDefaultsAndSkips() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = TestDataUtility.createLead('AutoRequest Defaults');
            ld.Project_Request_Submitted__c = false;
            update ld;

            Interior_Room__c room = getRoom();

            List<Object> rooms = new List<Object>{
                new Map<String, Object>{ 'roomId' => room.Id },                  // default qty = 1
                new Map<String, Object>{ 'roomId' => room.Id, 'quantity' => 0 }, // qty < 1 -> 1
                new Map<String, Object>{ 'roomId' => null, 'quantity' => 5 }     // skip
            };

            List<Object> designs = new List<Object>{
                new Map<String, Object>{ 'roomId' => room.Id, 'designId' => null }, // skip
                new Map<String, Object>{ 'roomId' => null,    'designId' => null }  // skip
            };

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'lastName' => 'Doe',
                'company' => 'Test Co',
                'rooms' => rooms,
                'selectedRoomDesigns' => designs
            };

            Test.startTest();
            InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            List<Interior_Request_Room__c> savedRooms =
                [SELECT Quantity__c FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
            System.assertEquals(2, savedRooms.size());

            Integer minQty = 999;
            for (Interior_Request_Room__c rr : savedRooms) {
                minQty = Math.min(minQty, Integer.valueOf(String.valueOf(rr.Quantity__c)));
            }
            System.assertEquals(1, minQty);

            Integer designCount =
                [SELECT Count() FROM Interior_Request_Room_Design__c WHERE Lead__c = :ld.Id];
            System.assertEquals(0, designCount);
        }
    }

    @IsTest
    static void testSaveRequestDoubleSubmission() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = getLead();
            ld.Project_Request_Submitted__c = true;
            update ld;

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'lastName' => ld.LastName,
                'company' => ld.Company
            };

            Boolean caught = false;
            Test.startTest();
            try {
                InteriorAutoProjectRequestService.saveRequest(req);
            } catch (AuraHandledException e) {
                caught = true;
            }
            Test.stopTest();

            System.assertEquals(true, caught);
        }
    }

    @IsTest
    static void testSaveRequestValidations() {
        User u = getTestUser();
        System.runAs(u) {
            Boolean caughtNull = false;
            try {
                InteriorAutoProjectRequestService.saveRequest(null);
            } catch (AuraHandledException e) {
                caughtNull = true;
            }
            System.assertEquals(true, caughtNull);

            Boolean caughtMissingLead = false;
            try {
                InteriorAutoProjectRequestService.saveRequest(new Map<String, Object>{ 'firstName' => 'Test' });
            } catch (AuraHandledException e) {
                caughtMissingLead = true;
            }
            System.assertEquals(true, caughtMissingLead);
        }
    }

    /**
     * Covers deleteExistingChildRecords() when there ARE existing children
     * and save is called with empty children lists.
     */
    @IsTest
    static void testSaveRequestEmptyChildrenDeletes() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = TestDataUtility.createLead('AutoRequest Empty');
            ld.Project_Request_Submitted__c = false;
            update ld;

            Interior_Room__c room = getRoom();
            Interior_Design__c design = getDesign();

            insert new Interior_Request_Room__c(Lead__c = ld.Id, Interior_Room__c = room.Id, Quantity__c = 2);
            insert new Interior_Request_Room_Design__c(
                Lead__c = ld.Id, Interior_Room__c = room.Id, Interior_Design__c = design.Id, Quantity__c = 1
            );

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'lastName' => 'Smith',
                'company' => 'Smith Co',
                'rooms' => new List<Object>(),
                'selectedRoomDesigns' => new List<Object>()
            };

            Test.startTest();
            InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            System.assertEquals(0, [SELECT Count() FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id]);
            System.assertEquals(0, [SELECT Count() FROM Interior_Request_Room_Design__c WHERE Lead__c = :ld.Id]);
        }
    }


    /**
     * Covers the NEW logic (collectNonDuplicateErrors) indirectly:
     * - Pre-link the same ContentDocument to Lead
     * - Service should detect already linked and newLinks becomes empty
     * - It returns without throwing
     */
    @IsTest
    static void testSaveRequestFilesAlreadyLinkedNoThrow() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = TestDataUtility.createLead('AutoRequest FileAlreadyLinked');
            ld.Project_Request_Submitted__c = false;
            update ld;

            Interior_Room__c room = getRoom();
            Interior_Design__c design = getDesign();

            Id docId = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :design.Id
                LIMIT 1
            ].ContentDocumentId;

            insert new ContentDocumentLink(
                LinkedEntityId    = ld.Id,
                ContentDocumentId = docId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );

            Integer beforeCnt = [SELECT Count() FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id];

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'lastName' => 'FileSkip',
                'company' => 'FileSkip Co',
                'rooms' => new List<Object>{
                    new Map<String, Object>{ 'roomId' => room.Id, 'quantity' => 1 }
                },
                'selectedRoomDesigns' => new List<Object>{
                    new Map<String, Object>{ 'roomId' => room.Id, 'designId' => design.Id, 'quantity' => 1, 'lineAmount' => 100 }
                }
            };

            Test.startTest();
            InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            Integer afterCnt = [SELECT Count() FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id];

            // Should not add duplicate link and should not throw
            System.assertEquals(beforeCnt, afterCnt);
        }
    }

    /* =========================================================
       TESTS: FETCH METHODS
       ========================================================= */

    @IsTest
    static void testFetchLeadForAutoRequest() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = getLead();

            Test.startTest();
            Lead result = InteriorAutoProjectRequestService.fetchLeadForAutoRequest(ld.Id);
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertEquals(ld.Id, result.Id);
        }
    }

    @IsTest
    static void testFetchLeadExceptions() {
        User u = getTestUser();
        System.runAs(u) {
            Boolean caught = false;
            try {
                InteriorAutoProjectRequestService.fetchLeadForAutoRequest(null);
            } catch (AuraHandledException e) {
                caught = true;
            }
            System.assertEquals(true, caught);
        }
    }

    @IsTest
    static void testFetchExistingRequest() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = TestDataUtility.createLead('AutoRequest Existing');
            ld.Project_Request_Submitted__c = false;
            update ld;

            Interior_Room__c room = getRoom();
            Interior_Design__c design = getDesign();

            insert new Interior_Request_Room__c(Lead__c = ld.Id, Interior_Room__c = room.Id, Quantity__c = 3);
            insert new Interior_Request_Room_Design__c(
                Lead__c = ld.Id,
                Interior_Room__c = room.Id,
                Interior_Design__c = design.Id,
                Quantity__c = 2,
                Design_Amount__c = 250,
                Plan_Level__c = 'Standard',
                Room_Size_Sqft__c = 120,
                Template_Size_Sqft__c = 100,
                Rate_Per_Sqft__c = 50
            );

            Test.startTest();
            InteriorAutoProjectRequestService.ExistingRequestDTO dto =
                InteriorAutoProjectRequestService.fetchExistingRequest(ld.Id);
            Test.stopTest();

            System.assertNotEquals(null, dto);
            System.assertEquals(1, dto.rooms.size());
            System.assertEquals(1, dto.roomDesigns.size());
            System.assertEquals(room.Id, dto.rooms[0].roomId);
            System.assertEquals(3, dto.rooms[0].quantity);
            System.assertEquals(design.Id, dto.roomDesigns[0].designId);
        }
    }

    @IsTest
    static void testFetchExistingRequestExceptions() {
        User u = getTestUser();
        System.runAs(u) {
            Boolean caught = false;
            try {
                InteriorAutoProjectRequestService.fetchExistingRequest(null);
            } catch (AuraHandledException e) {
                caught = true;
            }
            System.assertEquals(true, caught);
        }
    }

    /**
 * Reliable coverage booster (no flaky Lead failure):
 * Forces a DML failure in upsertRooms() by passing an INVALID roomId value.
 * This triggers:
 * - upsertRooms() -> Database.insert(..., false) with failures
 * - hasDbErrors(res) == true
 * - collectDbErrors(res) aggregation
 * - AuraHandledException thrown ("Unable to save selected rooms: ...")
 */
@IsTest
static void testSaveRequestRoomInsertFailureCoversDbErrorCollectors() {
    User u = getTestUser();
    System.runAs(u) {
        // Fresh lead (not submitted)
        Lead ld = TestDataUtility.createLead('AutoRequest RoomFail');
        ld.Project_Request_Submitted__c = false;
        update ld;

        // Invalid Id (syntactically valid 15/18 chars, but wrong SObject type for Interior_Room__c lookup)
        // Using a Lead Id here guarantees INVALID_CROSS_REFERENCE_KEY / FIELD_INTEGRITY_EXCEPTION.
        String invalidRoomId = ld.Id;

        List<Object> rooms = new List<Object>{
            new Map<String, Object>{ 'roomId' => invalidRoomId, 'quantity' => 1 }
        };

        Map<String, Object> req = new Map<String, Object>{
            'leadId' => ld.Id,
            'lastName' => 'RoomFail',
            'company'  => 'RoomFail Co',
            'rooms' => rooms,
            'selectedRoomDesigns' => new List<Object>()
        };

        Boolean caught = false;

        Test.startTest();
        try {
            InteriorAutoProjectRequestService.saveRequest(req);
        } catch (AuraHandledException e) {
            caught = true;
            // Message text may vary, but it MUST throw.
            System.assert(String.isNotBlank(e.getMessage()), 'Expected error message.');
        }
        Test.stopTest();

        System.assertEquals(true, caught, 'Expected AuraHandledException due to invalid roomId.');
    }
}
}