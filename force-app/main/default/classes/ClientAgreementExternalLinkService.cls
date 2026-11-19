/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementExternalLinkService
 * Author          : Arelia
 * Created Date    : Oct 8, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 8, 2026
 * Description     : Validates and formats external supporting file links for Client Agreements.
 */

public inherited sharing class ClientAgreementExternalLinkService {

    private static final Integer MAX_TEXT_LENGTH = 32768;
    private static final Integer MAX_LINKS = 20;

    /**
     * @description Validates and normalizes sharing links.
     * @param inputLinks Multiline link input.
     * @return Validated links separated by newlines.
     */
    public static String validateLinks(String inputLinks) {

        if (String.isBlank(inputLinks)) {
            return null;
        }

        if (inputLinks.length() > MAX_TEXT_LENGTH) {
            throw new AuraHandledException(
                'External supporting links exceed the maximum length.'
            );
        }

        List<String> validatedLinks = new List<String>();
        Set<String> uniqueLinks = new Set<String>();

        String normalizedText = inputLinks
            .replace('\r\n', '\n')
            .replace('\r', '\n');

        for (String line : normalizedText.split('\n')) {

            String link = line.trim();

            if (String.isBlank(link)) {
                continue;
            }

            validateSingleLink(link);

            if (!uniqueLinks.contains(link)) {
                uniqueLinks.add(link);
                validatedLinks.add(link);
            }

            if (validatedLinks.size() > MAX_LINKS) {
                throw new AuraHandledException(
                    'A maximum of 20 external supporting links is allowed.'
                );
            }
        }

        return validatedLinks.isEmpty()
            ? null
            : String.join(validatedLinks, '\n');
    }
    
    /**
    * @description Validates approved HTTPS sharing URL formats.
    * @param link External supporting file URL.
    */
    private static void validateSingleLink(String link) {

        if (
            !link.startsWithIgnoreCase('https://') ||
            Pattern.compile('\\s').matcher(link).find() ||
            link.contains('<') ||
            link.contains('>') ||
            link.contains('"') ||
            link.contains('\'')
        ) {
            throw new AuraHandledException(
                'Each external supporting link must be a valid HTTPS URL.'
            );
        }

        Pattern urlPattern = Pattern.compile(
            '(?i)^https://([^/?#:\\s]+)([/?#].*)?$'
        );

        Matcher matcher = urlPattern.matcher(link);

        if (!matcher.matches()) {
            throw new AuraHandledException(
                'Invalid external supporting file link.'
            );
        }

        String host = matcher.group(1).toLowerCase();

        String pathAndQuery = matcher.group(2) == null
            ? ''
            : matcher.group(2);

        Boolean isGoogleDrive =
            host == 'drive.google.com' ||
            host == 'docs.google.com';

        Boolean isOneDrive =
            host == '1drv.ms' ||
            host == 'onedrive.live.com' ||
            host.endsWith('.sharepoint.com');

        if (!isGoogleDrive && !isOneDrive) {
            throw new AuraHandledException(
                'Only Google Drive and OneDrive sharing links are allowed.'
            );
        }

        if (!isRecognizedSharingUrl(host, pathAndQuery)) {
            throw new AuraHandledException(
                'Invalid Google Drive or OneDrive sharing link format.'
            );
        }
    }

    /**
    * @description Recognizes common sharing URL structures.
    * @param host Approved provider hostname.
    * @param pathAndQuery URL path and query string.
    * @return True when the URL has a supported sharing format.
    */
    private static Boolean isRecognizedSharingUrl(
        String host,
        String pathAndQuery
    ) {

        if (host == 'drive.google.com') {

            return matchesUrlPattern(
                pathAndQuery,
                '^/file/d/[^/?#]+(?:[/?#].*)?$'
            ) ||
            matchesUrlPattern(
                pathAndQuery,
                '^/drive/(?:u/[0-9]+/)?folders/[^/?#]+(?:[/?#].*)?$'
            ) ||
            matchesUrlPattern(
                pathAndQuery,
                '^/open\\?id=[^&#]+(?:&.*)?$'
            );
        }

        if (host == 'docs.google.com') {

            return matchesUrlPattern(
                pathAndQuery,
                '^/(?:document|spreadsheets|presentation|forms)/d/' +
                '[^/?#]+(?:[/?#].*)?$'
            );
        }

        if (host == '1drv.ms') {

            return matchesUrlPattern(
                pathAndQuery,
                '^/(?:[a-z]/)?s![a-z0-9_-]+(?:[/?#].*)?$'
            ) ||
            matchesUrlPattern(
                pathAndQuery,
                '^/:[a-z]:/(?:g|r|s)/[^?#]+(?:[?#].*)?$'
            );
        }

        if (host == 'onedrive.live.com') {

            Boolean validPath =
                matchesUrlPattern(
                    pathAndQuery,
                    '^/(?:\\?.*|(?:redir|view\\.aspx|' +
                    'edit\\.aspx|download|embed)\\?.*)$'
                );

            Boolean hasFileIdentifier =
                Pattern.compile(
                    '(?i)(?:\\?|&)(?:id|resid)=[^&#]+'
                ).matcher(pathAndQuery).find();

            return validPath && hasFileIdentifier;
        }

        if (host.endsWith('.sharepoint.com')) {

            return matchesUrlPattern(
                pathAndQuery,
                '^/(?:sites|teams|personal)/[^/?#]+/.+'
            ) ||
            matchesUrlPattern(
                pathAndQuery,
                '^/:[a-z]:/(?:g|r|s)/[^?#]+(?:[?#].*)?$'
            );
        }

        return false;
    }

    /**
    * @description Matches a path against a case-insensitive pattern.
    * @param value Path or query to validate.
    * @param expression Regular expression.
    * @return True when the pattern matches.
    */
    private static Boolean matchesUrlPattern(
        String value,
        String expression
    ) {

        return Pattern.compile(
            '(?i)' + expression
        ).matcher(value).matches();
    }
    
	/**
	* @description Builds clickable external supporting links.
	* @param storedLinks Previously validated links.
	* @return HTML links or an empty string.
	*/
	public static String buildEmailHtml(String storedLinks) {

		if (String.isBlank(storedLinks)) {
			return '';
		}

		List<String> formattedLinks = new List<String>();

		for (String line : storedLinks.split('\n')) {

			String link = line.trim();

			if (String.isBlank(link)) {
				continue;
			}

			String safeLink = escapeHtml(link);

			formattedLinks.add(
				'<a href="' + safeLink + '">' +
				safeLink +
				'</a>'
			);
		}

		return String.join(formattedLinks, '<br/>');
	}


    /**
     * @description Escapes URL content for HTML output.
     */
    private static String escapeHtml(String value) {

        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}