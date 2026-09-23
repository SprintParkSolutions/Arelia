/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementTemplateService
 * Author          : <YourName>
 * Created Date    : Jul 6, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 6, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 6, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public inherited sharing class VendorAgreementTemplateService {

    public static String buildAgreementHtml(
        Vendor_Opportunity__c vendorOpportunity
    ) {
        String vendorName = VendorAgreementUtil.escapeHtml(
            getSafeValue(vendorOpportunity.Vendor__r.Name)
        );

        String vendorEmail = VendorAgreementUtil.escapeHtml(
            getSafeValue(vendorOpportunity.Vendor__r.Email__c)
        );

        String vendorContactNumber = VendorAgreementUtil.escapeHtml(
            getSafeValue(vendorOpportunity.Vendor__r.Phone__c)
        );

        String vendorCategory = VendorAgreementUtil.escapeHtml(
            getSafeValue(vendorOpportunity.Vendor_Category__c)
        );

        String opportunityName = VendorAgreementUtil.escapeHtml(
            getSafeValue(vendorOpportunity.Opportunity__r.Name)
        );

        String vendorAddress = VendorAgreementUtil.escapeHtml(
            getSafeValue(vendorOpportunity.Vendor__r.Address__c)
        );

        return
            '<div class="agreement-page">'
            + '<div class="agreement-header">'
            + '<div class="company-name">ARELIA SPACE</div>'
            + '<div class="agreement-title">VENDOR AGREEMENT</div>'
            + '<div class="agreement-subtitle">'
            + 'Interior Design Vendor / Contractor Agreement'
            + '</div>'
            + '</div>'

            + '<table class="reference-table">'
            + referenceRow('Project', opportunityName)
            + referenceRow('Vendor Name', vendorName)
            + referenceRow('Vendor Email', vendorEmail)
            + referenceRow('Vendor Contact Number', vendorContactNumber)
            + referenceRow('Vendor Category', vendorCategory)
            + referenceRow('Agreement Date', String.valueOf(Date.today()))
            + '</table>'

            + section(
                '1. Parties',
                'This Vendor Agreement (&quot;Agreement&quot;) is entered into '
                + 'between Arelia Space (&quot;Company&quot;) and the '
                + 'Vendor/Contractor (&quot;Vendor&quot;) for execution of works '
                + 'related to interior design projects, including but not limited '
                + 'to carpentry, electrical, plumbing, painting, false ceiling, '
                + 'flooring, fabrication, civil work, and allied services.'
            )

            + section(
                '2. Scope of Work',
                'Vendor shall perform assigned work orders, drawings, '
                + 'specifications, BOQs, and project instructions provided by '
                + 'the Company. Vendor shall complete work in accordance with '
                + 'industry standards and approved designs.'
            )

            + listSection(
                '3. Vendor Responsibilities',
                new List<String>{
                    'Provide skilled manpower, tools, equipment, and supervision.',
                    'Follow approved drawings and specifications.',
                    'Maintain quality standards and workmanship.',
                    'Comply with all safety requirements.',
                    'Coordinate with project managers and site engineers.',
                    'Maintain cleanliness and proper waste disposal.'
                }
            )

            + section(
                '4. Quality Standards',
                'All work shall meet Company quality standards. Defective work '
                + 'shall be rectified at Vendor&rsquo;s cost. The Company reserves '
                + 'the right to reject substandard work and materials.'
            )

            + section(
                '5. Materials',
                'Where materials are supplied by the Company, Vendor shall be '
                + 'responsible for proper handling and storage. Any wastage beyond '
                + 'approved limits may be recovered from Vendor payments.'
            )

            + section(
                '6. Project Schedule',
                'Vendor shall adhere to project timelines. Delays attributable '
                + 'to Vendor may result in penalties, replacement of Vendor, or '
                + 'recovery of consequential costs incurred by the Company.'
            )

            + listSection(
                '7. Payment Terms',
                new List<String>{
                    'Payments shall be based on approved work completion milestones.',
                    'Vendor must submit invoices with supporting measurements and approvals.',
                    'Retention amounts may be withheld until project completion and defect liability period expiry.',
                    'Company may deduct penalties, damages, or material losses from payable amounts.'
                }
            )

            + section(
                '8. Safety and Compliance',
                'Vendor shall comply with all applicable laws, labour '
                + 'regulations, workplace safety requirements, insurance '
                + 'obligations, and statutory registrations. Vendor is solely '
                + 'responsible for its workforce.'
            )

            + section(
                '9. Workforce and Conduct',
                'Vendor shall ensure professional conduct of workers at project '
                + 'sites. The Company may request removal of any worker for '
                + 'misconduct, safety violations, or poor performance.'
            )

            + section(
                '10. Confidentiality',
                'Vendor shall maintain confidentiality of client information, '
                + 'drawings, pricing, designs, business processes, and project '
                + 'documentation. Confidential information shall not be disclosed '
                + 'without written approval.'
            )

            + section(
                '11. Non-Solicitation',
                'Vendor shall not directly approach, solicit, contract with, or '
                + 'perform work for Company clients introduced through Company '
                + 'projects without prior written consent.'
            )

            + section(
                '12. Warranty and Defect Liability',
                'Vendor shall provide a minimum defect liability period of '
                + '12 months from work completion unless otherwise specified. '
                + 'Vendor shall rectify defects within a reasonable timeframe at '
                + 'no additional cost.'
            )

            + section(
                '13. Variations and Change Orders',
                'Any additional work, modifications, upgrades, or deviations '
                + 'from approved scope shall require written approval before '
                + 'execution and billing.'
            )

            + section(
                '14. Insurance and Liability',
                'Vendor shall be liable for damages caused by negligence, '
                + 'defective workmanship, property damage, or injury caused by '
                + 'Vendor personnel. Company shall not be liable for Vendor '
                + 'employee claims.'
            )

            + section(
                '15. Intellectual Property',
                'All drawings, designs, specifications, BOQs, renderings, and '
                + 'project documents remain the exclusive property of the Company '
                + 'and its clients.'
            )

            + section(
                '16. Termination',
                'The Company may terminate this Agreement for poor performance, '
                + 'quality issues, delays, safety violations, breach of '
                + 'confidentiality, or misconduct. Upon termination, Vendor shall '
                + 'immediately hand over work, materials, and project documentation.'
            )

            + section(
                '17. Dispute Resolution',
                'Parties shall first attempt amicable resolution. Failing '
                + 'resolution, disputes shall be subject to arbitration and '
                + 'jurisdiction of competent courts as mutually agreed.'
            )

            + listSection(
                '18. General Terms',
                new List<String>{
                    'Vendor acts as an independent contractor.',
                    'No partnership, employment, or agency relationship is created.',
                    'Amendments must be in writing and signed by both parties.',
                    'This Agreement constitutes the entire understanding between the parties.'
                }
            )

            + '<div class="vendor-details">'
            + '<h2>Vendor Details</h2>'
            + '<table class="details-table">'
            + referenceRow('Vendor Name', vendorName)
            + referenceRow('Vendor Email', vendorEmail)
            + referenceRow('Vendor Contact Number', vendorContactNumber)
            + referenceRow('Vendor Category', vendorCategory)
            + referenceRow('Address', vendorAddress)
            // + referenceRow('GST Number', '')
            + '</table>'
            + '</div>'

            + '<div class="signature-block">'
            + '<div class="signature-column">'
            + '<h3>For the Vendor</h3>'
            + '<div class="signature-space"></div>'
            + '<p><strong>Name:</strong> ' + vendorName + '</p>'
            + '<p><strong>Vendor Category:</strong> ' + vendorCategory + '</p>'
            + '</div>'
            + '</div>'

            + '<div class="agreement-footer">'
            + 'Arelia Space | Vendor Agreement | Confidential'
            + '</div>'
            + '</div>';
    }

    private static String referenceRow(
        String label,
        String value
    ) {
        String safeLabel = VendorAgreementUtil.escapeHtml(
            getSafeValue(label)
        );

        String safeValue = String.isBlank(value)
            ? '&nbsp;'
            : value;

        return '<tr><td><strong>' + safeLabel + '</strong></td>'
            + '<td>' + safeValue + '</td></tr>';
    }

    private static String section(
        String title,
        String content
    ) {
        return '<div class="agreement-section">'
            + '<h2>' + title + '</h2>'
            + '<p>' + content + '</p>'
            + '</div>';
    }

    private static String listSection(
        String title,
        List<String> items
    ) {
        String html = '<div class="agreement-section">'
            + '<h2>' + title + '</h2><ul>';

        for (String item : items) {
            html += '<li>' + VendorAgreementUtil.escapeHtml(item) + '</li>';
        }

        return html + '</ul></div>';
    }

    private static String getSafeValue(String value) {
        return String.isBlank(value) ? '' : value;
    }

    private VendorAgreementTemplateService() {
    }
}