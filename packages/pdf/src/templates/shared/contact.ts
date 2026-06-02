type WebsiteDisplay = {
	url: string;
	label?: string | undefined;
};

type CustomFieldLink = {
	link?: string | undefined;
};

type CustomFieldDisplay = {
	text?: string | undefined;
	link?: string | undefined;
	icon?: string | undefined;
};

export const getWebsiteDisplayText = (website: WebsiteDisplay): string => {
	const label = website.label?.trim();

	return label || website.url;
};

export const getCustomFieldLinkUrl = (field: CustomFieldLink): string | undefined => {
	const link = field.link?.trim();
	if (link) return link;

	// Fall back to text if it looks like a URL
	const text = (field as CustomFieldDisplay).text?.trim();
	if (text?.startsWith("http")) return text;

	return undefined;
};

const KNOWN_NETWORKS: Record<string, string> = {
	github: "GitHub",
	linkedin: "LinkedIn",
	twitter: "Twitter",
	facebook: "Facebook",
	instagram: "Instagram",
	youtube: "YouTube",
};

export const getCustomFieldDisplayText = (field: CustomFieldDisplay): string => {
	const text = field.text?.trim();

	// If text is already short (not a URL), use it as-is
	if (text && !text.startsWith("http")) return text;

	// Check icon slug for known network names
	const icon = field.icon?.toLowerCase() ?? "";
	for (const [key, label] of Object.entries(KNOWN_NETWORKS)) {
		if (icon.includes(key)) return label;
	}

	// Check link URL for known network names
	const link = field.link?.toLowerCase() ?? "";
	for (const [key, label] of Object.entries(KNOWN_NETWORKS)) {
		if (link.includes(`${key}.com`)) return label;
	}

	return text || "";
};
