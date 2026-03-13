import { LightningElement } from "lwc";

import INSTAGRAM_URL from '@salesforce/label/c.Instagram_URL';
import FACEBOOK_URL from '@salesforce/label/c.Facebook_URL';
import LINKEDIN_URL from '@salesforce/label/c.LinkedIn_URL';

import FOOTER_EMAIL from '@salesforce/label/c.Footer_Email';
import FOOTER_PHONE from '@salesforce/label/c.Footer_Phone';
import FOOTER_LOCATION from '@salesforce/label/c.Footer_Location';
import FOOTER_WORKING_HOURS from '@salesforce/label/c.Footer_Working_Hours';

const SVG = {
  MapPin: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><path d="M12 21s6-5.433 6-10A6 6 0 0 0 6 11c0 4.567 6 10 6 10z" stroke="currentColor" stroke-width="1.4"></path><circle cx="12" cy="11" r="2.5" fill="currentColor"></circle></svg>`,
  Phone: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><path d="M22 16.92v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 3 5.18 2 2 0 0 1 5 3h3a2 2 0 0 1 2 1.72l.76 2.56a2 2 0 0 1-.45 2.11L9.9 10.1a16 16 0 0 0 4 4l1.7-1.7a2 2 0 0 1 2.11-.45l2.56.76A2 2 0 0 1 22 16.92z" stroke="currentColor" stroke-width="1.4"></path></svg>`,
  Mail: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><rect x="3" y="5" width="18" height="14" rx="2" stroke="currentColor" stroke-width="1.4"></rect><polyline points="3,7 12,13 21,7" stroke="currentColor" stroke-width="1.4" fill="none"></polyline></svg>`,
  Clock: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.4"></circle><path d="M12 7v6l4 2" stroke="currentColor" stroke-width="1.4"></path></svg>`,
  Instagram: `<svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
              <path d="M7.75 2h8.5C19.44 2 22 4.56 22 7.75v8.5C22 19.44 19.44 22 16.25 22h-8.5C4.56 22 2 19.44 2 16.25v-8.5C2 4.56 4.56 2 7.75 2zm8.25 2h-8c-2.21 0-4 1.79-4 4v8c0 2.21 1.79 4 4 4h8c2.21 0 4-1.79 4-4v-8c0-2.21-1.79-4-4-4zm-4 3.5A5.5 5.5 0 1 1 6.5 13 5.51 5.51 0 0 1 12 7.5zm0 2A3.5 3.5 0 1 0 15.5 13 3.5 3.5 0 0 0 12 9.5zm4.75-3.25a1.25 1.25 0 1 1-1.25 1.25 1.25 1.25 0 0 1 1.25-1.25z"/>
              </svg>`,
  Facebook: `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M22 12a10 10 0 1 0-11.5 9.9v-7H8.1V12h2.4V9.7c0-2.4 1.4-3.8 3.6-3.8h2v2.2h-1.1c-1.1 0-1.4.7-1.4 1.4V12h2.4l-.4 2.9h-2V22A10 10 0 0 0 22 12z"></path></svg>`,
  Linkedin: `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M4.98 3.5a2.5 2.5 0 1 1 .02 0zM3 8.98h3.96V21H3V8.98zM9.5 8.98H13v1.6h.06c.47-.9 1.62-1.86 3.34-1.86 3.56 0 4.2 2.34 4.2 5.38V21H17.2v-5.2c0-1.24-.02-2.84-1.72-2.84-1.72 0-1.98 1.34-1.98 2.74V21H9.5z"></path></svg>`
};

export default class ContactSection extends LightningElement {
  instagramURL = INSTAGRAM_URL;
  facebookURL = FACEBOOK_URL;
  linkedinURL = LINKEDIN_URL;

  /* Footer labels */
  email = FOOTER_EMAIL;
  phone = FOOTER_PHONE;
  location = FOOTER_LOCATION;
  workingHours = FOOTER_WORKING_HOURS;

  parseLines(value) {
    if (!value) {
      return [];
    }

    return value
      .split(/\r?\n|;/)
      .map(item => item.trim())
      .filter(item => item);
  }

  parseContactValues(value) {
    if (!value) {
      return [];
    }

    return value
      .split(/\r?\n|;|,/)
      .map(item => item.trim())
      .filter(item => item);
  }

  get contactDetails() {
    return [
      {
        title: "Visit Our Studio",
        svg: SVG.MapPin,
        lines: this.parseLines(this.location)
      },
      {
        title: "Call Us",
        svg: SVG.Phone,
        lines: this.parseContactValues(this.phone)
      },
      {
        title: "Email Us",
        svg: SVG.Mail,
        lines: this.parseContactValues(this.email)
      },
      {
        title: "Working Hours",
        svg: SVG.Clock,
        lines: this.parseLines(this.workingHours)
      }
    ];
  }

  get socialLinks() {
    return [
      { label: "Instagram", svg: SVG.Instagram, href: this.instagramURL },
      { label: "Facebook", svg: SVG.Facebook, href: this.facebookURL },
      { label: "LinkedIn", svg: SVG.Linkedin, href: this.linkedinURL }
    ];
  }

  renderedCallback() {
    this.injectSVGs();
  }

  injectSVGs() {
    // Contact cards
    this.contactDetails.forEach((d) => {
      const target = this.template.querySelector(`span[data-key="${d.title}"]`);
      if (target && target.innerHTML !== d.svg) {
        target.innerHTML = d.svg;
      }
    });

    // Social icons
    this.socialLinks.forEach((s) => {
      const target = this.template.querySelector(`span[data-key="${s.label}"]`);
      if (target && target.innerHTML !== s.svg) {
        target.innerHTML = s.svg;
      }
    });
  }
}