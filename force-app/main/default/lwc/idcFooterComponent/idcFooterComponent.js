import { LightningElement } from 'lwc';
import IdcLogo from '@salesforce/resourceUrl/Arelia_Footer_Logo';
import InstagramIcon from '@salesforce/resourceUrl/InstagramIcon';
import FacebookIcon from '@salesforce/resourceUrl/FacebookIcon';
import LinkedinIcon from '@salesforce/resourceUrl/LinkedinIcon';

import RESIDENTIAL_URL from '@salesforce/label/c.Residential_URL';
import COMMERCIAL_URL from '@salesforce/label/c.Commercial_URL';
import HOSPITALITY_URL from '@salesforce/label/c.Hospitality_URL';

import INSTAGRAM_URL from '@salesforce/label/c.Instagram_URL';
import FACEBOOK_URL from '@salesforce/label/c.Facebook_URL';
import LINKEDIN_URL from '@salesforce/label/c.LinkedIn_URL';

import SITE_BASE_URL from '@salesforce/label/c.Arelia_Site_Label';

/* NEW LABELS */
import FOOTER_EMAIL from '@salesforce/label/c.Footer_Email';
import FOOTER_PHONE from '@salesforce/label/c.Footer_Phone';
import FOOTER_LOCATION from '@salesforce/label/c.Footer_Location';
import FOOTER_COPYRIGHT from '@salesforce/label/c.Footer_Copyright';

export default class IdcFooterComponent extends LightningElement {

    logoUrl = IdcLogo;
    instagramIcon = InstagramIcon;
    facebookIcon = FacebookIcon;
    linkedinIcon = LinkedinIcon;

    baseUrl = SITE_BASE_URL;

    /* Footer labels */
    email = FOOTER_EMAIL;
    phone = FOOTER_PHONE;
    location = FOOTER_LOCATION;
    copyright = FOOTER_COPYRIGHT;

    get residentialUrl() {
        return this.baseUrl + RESIDENTIAL_URL;
    }

    get commercialUrl() {
        return this.baseUrl + COMMERCIAL_URL;
    }

    get hospitalityUrl() {
        return this.baseUrl + HOSPITALITY_URL;
    }

    instagramUrl = INSTAGRAM_URL;
    facebookUrl = FACEBOOK_URL;
    linkedinUrl = LINKEDIN_URL;
}