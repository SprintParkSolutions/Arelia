/**
 * -----------------------------------------------------------------------------
 * Class Name      : ClientAgreementExternalLinkServiceTest
 * Author          : Arelia
 * Created Date    : Oct 9, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 13, 2026
 * Description     : Unit tests for ClientAgreementExternalLinkService.
 *                   Validates supported sharing URL formats, invalid URLs,
 *                   normalization, duplicates, link-count and length limits,
 *                   and email HTML formatting.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ClientAgreementExternalLinkServiceTest {

    private static final Integer MAX_LINKS = 20;
    private static final Integer MAX_TEXT_LENGTH = 32768;

    private static final String GOOGLE_DRIVE_URL =
        'https://drive.google.com/file/d/test123/view';

    private static final String GOOGLE_DOCS_URL =
        'https://docs.google.com/document/d/test123/edit';

    private static final String ONEDRIVE_URL =
        'https://onedrive.live.com/?id=test123';

    private static final String ONEDRIVE_SHORT_URL =
        'https://1drv.ms/u/s!test123';

    private static final String SHAREPOINT_URL =
        'https://company.sharepoint.com/sites/project/file.pdf';

    /**
     * @description Verifies blank input handling.
     */
    @IsTest
    static void blankLinksReturnNull() {

        System.assertEquals(
            null,
            ClientAgreementExternalLinkService.validateLinks(null),
            'Null input must return null.'
        );

        System.assertEquals(
            null,
            ClientAgreementExternalLinkService.validateLinks(''),
            'Empty input must return null.'
        );

        System.assertEquals(
            null,
            ClientAgreementExternalLinkService.validateLinks('   \n   '),
            'Whitespace-only input must return null.'
        );
    }

    /**
     * @description Verifies supported provider URLs.
     */
    @IsTest
    static void validSharingHostsAreAccepted() {

        List<String> links = new List<String>{
            GOOGLE_DRIVE_URL,
            GOOGLE_DOCS_URL,
            ONEDRIVE_URL,
            ONEDRIVE_SHORT_URL,
            SHAREPOINT_URL
        };

        String inputLinks = String.join(links, '\n');

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLinks
            );

        System.assertEquals(
            inputLinks,
            actualResult,
            'All supported sharing URLs must be accepted.'
        );
    }

    /**
     * @description Verifies Google Drive file, folder,
     * and open-link formats.
     */
    @IsTest
    static void googleDriveSharingFormatsAreAccepted() {

        List<String> validLinks = new List<String>{
            GOOGLE_DRIVE_URL,
            'https://drive.google.com/file/d/abc123/preview',
            'https://drive.google.com/file/d/abc123/view?usp=sharing',
            'https://drive.google.com/drive/folders/folder123',
            'https://drive.google.com/drive/u/0/folders/folder123',
            'https://drive.google.com/open?id=file123'
        };

        assertValidLinks(validLinks);
    }

    /**
     * @description Verifies supported Google Docs,
     * Sheets, Slides, and Forms formats.
     */
    @IsTest
    static void googleDocsSharingFormatsAreAccepted() {

        List<String> validLinks = new List<String>{
            GOOGLE_DOCS_URL,
            'https://docs.google.com/spreadsheets/d/sheet123/edit',
            'https://docs.google.com/presentation/d/slide123/edit',
            'https://docs.google.com/forms/d/form123/viewform'
        };

        assertValidLinks(validLinks);
    }

    /**
     * @description Verifies OneDrive standard
     * sharing URL formats.
     */
    @IsTest
    static void oneDriveSharingFormatsAreAccepted() {

        List<String> validLinks = new List<String>{
            ONEDRIVE_URL,
            'https://onedrive.live.com/?resid=ABC123',
            'https://onedrive.live.com/?id=ABC123&authkey=XYZ',
            'https://onedrive.live.com/redir?id=ABC123',
            'https://onedrive.live.com/view.aspx?resid=ABC123',
            'https://onedrive.live.com/edit.aspx?id=ABC123',
            'https://onedrive.live.com/download?id=ABC123',
            'https://onedrive.live.com/embed?resid=ABC123'
        };

        assertValidLinks(validLinks);
    }

    /**
     * @description Verifies supported OneDrive
     * shortened sharing URLs.
     */
    @IsTest
    static void oneDriveShortLinksAreAccepted() {

        List<String> validLinks = new List<String>{
            ONEDRIVE_SHORT_URL,
            'https://1drv.ms/s!test123',
            'https://1drv.ms/x/s!sheet123',
            'https://1drv.ms/:b:/g/personal/file123',
            'https://1drv.ms/:f:/r/personal/folder123',
            'https://1drv.ms/:w:/s/site/document123'
        };

        assertValidLinks(validLinks);
    }

    /**
     * @description Verifies SharePoint site,
     * team, personal, and sharing URL formats.
     */
    @IsTest
    static void sharePointSharingFormatsAreAccepted() {

        List<String> validLinks = new List<String>{
            SHAREPOINT_URL,
            'https://company.sharepoint.com/teams/design/file.pdf',
            'https://company.sharepoint.com/personal/user/file.pdf',
            'https://company.sharepoint.com/:b:/g/sites/project/file123',
            'https://company.sharepoint.com/:x:/r/sites/project/file123',
            'https://company.sharepoint.com/:w:/s/project/file123'
        };

        assertValidLinks(validLinks);
    }

    /**
     * @description Verifies case-insensitive
     * URL scheme and host matching.
     */
    @IsTest
    static void mixedCaseUrlsAreAccepted() {

        String inputLink =
            'HTTPS://DRIVE.GOOGLE.COM/file/d/test123/view';

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLink
            );

        System.assertEquals(
            inputLink,
            actualResult,
            'Mixed-case HTTPS URLs must be accepted.'
        );
    }

    /**
     * @description Verifies CRLF and CR
     * normalization.
     */
    @IsTest
    static void differentLineEndingsAreNormalized() {

        String inputLinks =
            GOOGLE_DRIVE_URL + '\r\n' +
            ONEDRIVE_URL + '\r' +
            GOOGLE_DOCS_URL;

        String expectedResult =
            GOOGLE_DRIVE_URL + '\n' +
            ONEDRIVE_URL + '\n' +
            GOOGLE_DOCS_URL;

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLinks
            );

        System.assertEquals(
            expectedResult,
            actualResult,
            'Line endings must be normalized to LF.'
        );
    }

    /**
     * @description Verifies blank-line removal
     * and surrounding whitespace trimming.
     */
    @IsTest
    static void blankLinesAndSpacesAreRemoved() {

        String inputLinks =
            '   ' + GOOGLE_DRIVE_URL + '   \n' +
            '\n' +
            '   \n' +
            '  ' + ONEDRIVE_URL + '  ';

        String expectedResult =
            GOOGLE_DRIVE_URL + '\n' +
            ONEDRIVE_URL;

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLinks
            );

        System.assertEquals(
            expectedResult,
            actualResult,
            'Whitespace and empty lines must be removed.'
        );
    }

    /**
     * @description Verifies duplicate removal
     * while preserving URL order.
     */
    @IsTest
    static void duplicateLinksAreRemoved() {

        String inputLinks =
            GOOGLE_DRIVE_URL + '\n' +
            ONEDRIVE_URL + '\n' +
            GOOGLE_DRIVE_URL + '\n' +
            ONEDRIVE_URL;

        String expectedResult =
            GOOGLE_DRIVE_URL + '\n' +
            ONEDRIVE_URL;

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLinks
            );

        System.assertEquals(
            expectedResult,
            actualResult,
            'Duplicate URLs must be removed.'
        );
    }

    /**
     * @description Verifies acceptance of
     * exactly 20 unique valid URLs.
     */
    @IsTest
    static void exactlyTwentyLinksAreAccepted() {

        List<String> links = buildUniqueLinks(MAX_LINKS);

        String inputLinks = String.join(links, '\n');

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLinks
            );

        System.assertEquals(
            inputLinks,
            actualResult,
            'Exactly 20 unique URLs must be accepted.'
        );

        System.assertEquals(
            MAX_LINKS,
            actualResult.split('\n').size(),
            'All 20 URLs must be retained.'
        );
    }

    /**
     * @description Verifies rejection of
     * more than 20 unique valid URLs.
     */
    @IsTest
    static void moreThanTwentyLinksAreRejected() {

        String inputLinks = String.join(
            buildUniqueLinks(MAX_LINKS + 1),
            '\n'
        );

        assertInvalidLinks(
            inputLinks,
            'More than 20 unique URLs must be rejected.'
        );
    }

    /**
     * @description Verifies that duplicate
     * entries do not increase unique URL count.
     */
    @IsTest
    static void duplicateEntriesDoNotExceedLimit() {

        List<String> links = buildUniqueLinks(MAX_LINKS);

        links.add(links[0]);
        links.add(links[1]);

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                String.join(links, '\n')
            );

        System.assertEquals(
            MAX_LINKS,
            actualResult.split('\n').size(),
            'Duplicate entries must not increase the unique count.'
        );
    }

    /**
     * @description Verifies rejection of input
     * exceeding 32,768 characters.
     */
    @IsTest
    static void oversizedInputIsRejected() {

        String oversizedInput =
            buildLongLink(MAX_TEXT_LENGTH + 1);

        System.assertEquals(
            MAX_TEXT_LENGTH + 1,
            oversizedInput.length(),
            'Test input must be 32,769 characters.'
        );

        assertInvalidLinks(
            oversizedInput,
            'URLs exceeding the maximum input length must be rejected.'
        );
    }

    /**
     * @description Verifies acceptance of
     * exactly 32,768 characters.
     */
    @IsTest
    static void maximumLengthInputIsAccepted() {

        String inputLink =
            buildLongLink(MAX_TEXT_LENGTH);

        String actualResult =
            ClientAgreementExternalLinkService.validateLinks(
                inputLink
            );

        System.assertEquals(
            MAX_TEXT_LENGTH,
            actualResult.length(),
            'Maximum-length input must be accepted.'
        );

        System.assertEquals(
            inputLink,
            actualResult,
            'Input content must remain unchanged.'
        );
    }

    /**
     * @description Verifies rejection of HTTP,
     * unsupported hosts, and malformed URLs.
     */
    @IsTest
    static void invalidUrlsAreRejected() {

        List<String> invalidLinks = new List<String>{
            'http://drive.google.com/file/d/test123/view',
            'https://youtube.com/watch?v=123',
            'https://drive.google.com.evil.com/file/123',
            'https://fake-sharepoint.com/file/123',
            'https://',
            'https:///file/123',
            'https://drive.google.com/file with spaces',
            'https://drive.google.com/file<123',
            'https://drive.google.com/file>123',
            'https://drive.google.com/file"123',
            'https://drive.google.com/file\'123',
            'https://drive.google.com:abc/file/d/test123/view',
            'https://drive.google.com/file/d/test\n123/view'
        };

        for (String invalidLink : invalidLinks) {

            assertInvalidLinks(
                invalidLink,
                'Invalid URL must be rejected: ' + invalidLink
            );
        }
    }

    /**
     * @description Verifies rejection of invalid
     * Google Drive sharing paths.
     */
    @IsTest
    static void invalidGoogleDriveFormatsAreRejected() {

        List<String> invalidLinks = new List<String>{
            'https://drive.google.com/invalid_test_link_12345',
            'https://drive.google.com/',
            'https://drive.google.com/file/d/',
            'https://drive.google.com/drive/folders/',
            'https://drive.google.com/open?id=',
            'https://drive.google.com/open?other=value',
            'https://drive.google.com/drive/u/test/folders/abc123'
        };

        assertInvalidLinkCollection(invalidLinks);
    }

    /**
     * @description Verifies rejection of invalid
     * Google Docs sharing paths.
     */
    @IsTest
    static void invalidGoogleDocsFormatsAreRejected() {

        List<String> invalidLinks = new List<String>{
            'https://docs.google.com/invalid_test_link_12345',
            'https://docs.google.com/document/d/',
            'https://docs.google.com/spreadsheets/d/',
            'https://docs.google.com/presentation/invalid123',
            'https://docs.google.com/forms/invalid123'
        };

        assertInvalidLinkCollection(invalidLinks);
    }

    /**
     * @description Verifies rejection of invalid
     * OneDrive sharing URL formats.
     */
    @IsTest
    static void invalidOneDriveFormatsAreRejected() {

        List<String> invalidLinks = new List<String>{
            'https://onedrive.live.com/invalid_test_link_12345',
            'https://onedrive.live.com/',
            'https://onedrive.live.com/?id=',
            'https://onedrive.live.com/?resid=',
            'https://onedrive.live.com/?other=test123',
            'https://onedrive.live.com/redir?other=test123',
            'https://onedrive.live.com/view.aspx',
            'https://onedrive.live.com/edit.aspx?other=test123',
            'https://onedrive.live.com/download?other=test123',
            'https://onedrive.live.com/embed?other=test123'
        };

        assertInvalidLinkCollection(invalidLinks);
    }

    /**
     * @description Specifically verifies the
     * invalid OneDrive URL reported during QA.
     */
    @IsTest
    static void invalidOneDriveSharingPathIsRejected() {

        String invalidLink =
            'https://onedrive.live.com/invalid_test_link_12345';

        assertInvalidLinks(
            invalidLink,
            'Unsupported OneDrive sharing paths must be rejected.'
        );
    }

    /**
     * @description Verifies rejection of invalid
     * OneDrive short-link formats.
     */
    @IsTest
    static void invalidOneDriveShortFormatsAreRejected() {

        List<String> invalidLinks = new List<String>{
            'https://1drv.ms/invalid_test_link_12345',
            'https://1drv.ms/',
            'https://1drv.ms/u/',
            'https://1drv.ms/s!',
            'https://1drv.ms/:b:/invalid/file123',
            'https://1drv.ms/:b:/g/'
        };

        assertInvalidLinkCollection(invalidLinks);
    }

    /**
     * @description Verifies rejection of invalid
     * SharePoint sharing paths.
     */
    @IsTest
    static void invalidSharePointFormatsAreRejected() {

        List<String> invalidLinks = new List<String>{
            'https://company.sharepoint.com/invalid_test_link_12345',
            'https://company.sharepoint.com/',
            'https://company.sharepoint.com/sites/',
            'https://company.sharepoint.com/teams/',
            'https://company.sharepoint.com/personal/',
            'https://company.sharepoint.com/:b:/invalid/file123'
        };

        assertInvalidLinkCollection(invalidLinks);
    }

    /**
     * @description Verifies rejection when valid
     * and invalid links are submitted together.
     */
    @IsTest
    static void mixedValidAndInvalidLinksAreRejected() {

        String inputLinks =
            GOOGLE_DRIVE_URL + '\n' +
            'https://onedrive.live.com/invalid_test_link_12345' + '\n' +
            ONEDRIVE_URL;

        assertInvalidLinks(
            inputLinks,
            'Mixed valid and invalid URLs must be rejected.'
        );
    }

    /**
     * @description Verifies that blank email
     * links generate empty HTML.
     */
    @IsTest
    static void blankEmailLinksReturnEmptyHtml() {

        System.assertEquals(
            '',
            ClientAgreementExternalLinkService.buildEmailHtml(null),
            'Null input must return empty HTML.'
        );

        System.assertEquals(
            '',
            ClientAgreementExternalLinkService.buildEmailHtml('   '),
            'Whitespace-only input must return empty HTML.'
        );

        System.assertEquals(
            '',
            ClientAgreementExternalLinkService.buildEmailHtml('\n\n'),
            'Blank lines must return empty HTML.'
        );
    }

    /**
     * @description Verifies clickable HTML
     * generation for stored links.
     */
    @IsTest
    static void validLinksGenerateClickableHtml() {

        String storedLinks =
            GOOGLE_DRIVE_URL + '\n' +
            ONEDRIVE_URL;

        String expectedHtml =
            '<a href="' + GOOGLE_DRIVE_URL + '">' +
            GOOGLE_DRIVE_URL + '</a><br/>' +
            '<a href="' + ONEDRIVE_URL + '">' +
            ONEDRIVE_URL + '</a>';

        String actualHtml =
            ClientAgreementExternalLinkService.buildEmailHtml(
                storedLinks
            );

        System.assertEquals(
            expectedHtml,
            actualHtml,
            'Email HTML must contain clickable URLs.'
        );
    }

    /**
     * @description Verifies whitespace handling
     * during email HTML generation.
     */
    @IsTest
    static void emailHtmlIgnoresBlankLines() {

        String storedLinks =
            '  ' + GOOGLE_DRIVE_URL + '  \n' +
            '\n' +
            '   \n' +
            '  ' + ONEDRIVE_URL + '  ';

        String expectedHtml =
            '<a href="' + GOOGLE_DRIVE_URL + '">' +
            GOOGLE_DRIVE_URL + '</a><br/>' +
            '<a href="' + ONEDRIVE_URL + '">' +
            ONEDRIVE_URL + '</a>';

        String actualHtml =
            ClientAgreementExternalLinkService.buildEmailHtml(
                storedLinks
            );

        System.assertEquals(
            expectedHtml,
            actualHtml,
            'Blank lines must be ignored and URLs trimmed.'
        );
    }

    /**
     * @description Verifies HTML special-character
     * escaping in hyperlink output.
     */
    @IsTest
    static void emailHtmlEscapesSpecialCharacters() {

        String inputLink =
            'https://drive.google.com/file?x=1&y=<tag>"\'';

        String actualHtml =
            ClientAgreementExternalLinkService.buildEmailHtml(
                inputLink
            );

        String escapedLink =
            'https://drive.google.com/file?x=1&amp;y=' +
            '&lt;tag&gt;&quot;&#39;';

        String expectedHtml =
            '<a href="' + escapedLink + '">' +
            escapedLink + '</a>';

        System.assertEquals(
            expectedHtml,
            actualHtml,
            'HTML special characters must be escaped.'
        );
    }

    /**
     * @description Verifies that query
     * parameters are HTML escaped.
     */
    @IsTest
    static void emailHtmlEscapesQueryParameters() {

        String storedLink =
            'https://onedrive.live.com/?id=123&authkey=ABC';

        String safeLink =
            'https://onedrive.live.com/?id=123&amp;authkey=ABC';

        String expectedHtml =
            '<a href="' + safeLink + '">' +
            safeLink + '</a>';

        String actualHtml =
            ClientAgreementExternalLinkService.buildEmailHtml(
                storedLink
            );

        System.assertEquals(
            expectedHtml,
            actualHtml,
            'Ampersands must be HTML escaped.'
        );
    }

    /**
     * @description Asserts that every URL
     * in a collection is accepted.
     * @param validLinks URLs expected to pass.
     */
    private static void assertValidLinks(
        List<String> validLinks
    ) {

        for (String validLink : validLinks) {

            String actualResult =
                ClientAgreementExternalLinkService.validateLinks(
                    validLink
                );

            System.assertEquals(
                validLink,
                actualResult,
                'Expected valid sharing URL: ' + validLink
            );
        }
    }

    /**
     * @description Asserts that every URL
     * in a collection is rejected.
     * @param invalidLinks URLs expected to fail.
     */
    private static void assertInvalidLinkCollection(
        List<String> invalidLinks
    ) {

        for (String invalidLink : invalidLinks) {

            assertInvalidLinks(
                invalidLink,
                'Invalid sharing URL must be rejected: ' +
                invalidLink
            );
        }
    }

    /**
     * @description Builds unique valid Google Drive URLs.
     * @param count Number of unique URLs to build.
     * @return List of valid-format URLs.
     */
    private static List<String> buildUniqueLinks(
        Integer count
    ) {

        List<String> links = new List<String>();

        for (Integer index = 0; index < count; index++) {

            links.add(
                'https://drive.google.com/file/d/test' +
                String.valueOf(index) +
                '/view'
            );
        }

        return links;
    }

    /**
     * @description Builds an exact-length synthetic
     * Google Drive URL for character-limit tests.
     * @param targetLength Required total length.
     * @return Synthetic URL of the requested length.
     */
    private static String buildLongLink(
        Integer targetLength
    ) {

        String result =
            'https://drive.google.com/file/d/';

        String chunk =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

        while (
            result.length() + chunk.length() <= targetLength
        ) {
            result += chunk;
        }

        while (result.length() < targetLength) {
            result += 'a';
        }

        return result;
    }

    /**
     * @description Verifies that invalid URLs
     * raise an AuraHandledException.
     * @param inputLinks Input to validate.
     * @param failureMessage Assertion failure message.
     */
    private static void assertInvalidLinks(
        String inputLinks,
        String failureMessage
    ) {

        Boolean exceptionThrown = false;

        try {

            ClientAgreementExternalLinkService.validateLinks(
                inputLinks
            );

        } catch (AuraHandledException exceptionValue) {

            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            failureMessage
        );
    }
}