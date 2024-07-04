<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" >
	<xsl:template match="/" >
		<xsl:apply-templates />
	</xsl:template>

	<xsl:template match="PackageSet/Package" >
		<xsl:apply-templates select="Submission/Submission" />
		<xsl:apply-templates select="ProjectLinks/Link" />
		<xsl:apply-templates select="Project/Project" />
	</xsl:template>

	<xsl:template match="Submission/Submission" >
		<h3 class="overview_title">SUBMITTER</h3>
		<table class="overview_table">
			<xsl:apply-templates select="Description/Organization" />
		</table>
	</xsl:template>

	<xsl:template match="ProjectLinks/Link" >
		<h3 class="overview_title">UMBRELLA INFO</h3>
		<table class="overview_table">
			<tr><td colspan="2"><h4>Umbrella BioProject</h4></td></tr>
			<tr><th>Umbrella BioProject accession</th><td>
			<xsl:for-each select="Hierarchical/MemberID">
				<xsl:if test="position() != 1">, </xsl:if>
				<a href="https://ddbj.nig.ac.jp/resource/bioproject/{@accession}" target="_blank"><xsl:value-of select="@accession" /></a>
			</xsl:for-each>
			<xsl:if test="(Hierarchical/MemberID/@accession != '') and (PeerProject/MemberID/@accession != '')">, </xsl:if>
			<xsl:for-each select="PeerProject/MemberID">
				<xsl:if test="position() != 1">, </xsl:if>
				<a href="https://ddbj.nig.ac.jp/resource/bioproject/{@accession}" target="_blank"><xsl:value-of select="@accession" /></a>
			</xsl:for-each>
			</td></tr>
		</table>
	</xsl:template>

	<xsl:template match="Description/Organization" >
		<xsl:for-each select="Contact">
			<tr><td colspan="2"><h4>Submitter <xsl:number level="single" format="1" count="Contact"/></h4></td></tr>
			<tr><th>First name</th><td><xsl:value-of select="Name/First" /></td></tr>
			<tr><th>Last name</th><td><xsl:value-of select="Name/Last" /></td></tr>
			<tr><th>E-mail</th><td><xsl:value-of select="@email" /></td></tr>
		</xsl:for-each>
		<tr><td colspan="2"><h4>Organization</h4></td></tr>
		<tr><th>Submitting organization</th><td><xsl:value-of select="Name" /></td></tr>
		<tr><th>Submitting organization URL</th><td><a href="{@url}" target="_blank"><xsl:value-of select="@url" /></a></td></tr>
	</xsl:template>

	<xsl:template match="Project/Project" >
		<xsl:if test="(ProjectDescr/ProjectReleaseDate != '') or (ProjectDescr/Title != '') or (ProjectDescr/Description != '') or (ProjectDescr/Relevance != '') or (ProjectDescr/ExternalLink != '') or (ProjectDescr/Grant != '') ">
			<h3 class="overview_title">GENERAL INFO</h3>
			<table class="overview_table">
				<xsl:apply-templates select="ProjectDescr/ProjectReleaseDate" />
				<xsl:if test="(ProjectDescr/Title != '') or (ProjectDescr/Description != '') or (ProjectDescr/Relevance != '') ">
					<tr><td colspan="2"><h4>Project Description</h4></td></tr>
					<xsl:apply-templates select="ProjectDescr/Title" />
					<xsl:apply-templates select="ProjectDescr/Description" />
					<xsl:apply-templates select="ProjectDescr/Relevance" />
				</xsl:if>
				<xsl:apply-templates select="ProjectDescr/ExternalLink" />
				<xsl:apply-templates select="ProjectDescr/Grant" />
			</table>
		</xsl:if>

		<xsl:if test="(ProjectType/ProjectTypeSubmission != '') or (ProjectDescr/LocusTagPrefix != '') ">
			<h3 class="overview_title">PROJECT TYPE</h3>
			<table class="overview_table">
				<xsl:apply-templates select="ProjectType/ProjectTypeSubmission/ProjectDataTypeSet" />
				<xsl:apply-templates select="ProjectType/ProjectTypeSubmission" />
				<xsl:apply-templates select="ProjectType/ProjectTypeSubmission/Method" />
				<xsl:apply-templates select="ProjectType/ProjectTypeSubmission/Objectives" />
				<xsl:apply-templates select="ProjectDescr/LocusTagPrefix" />
			</table>
		</xsl:if>

		<xsl:if test="(ProjectType/ProjectTypeSubmission/Target != '') or (ProjectType/ProjectTypeTopAdmin != '') ">
			<h3 class="overview_title">TARGET</h3>
			<table class="overview_table">
				<xsl:choose>
				<xsl:when test="(ProjectType/ProjectTypeSubmission/Target != '')">
					<xsl:apply-templates select="ProjectType/ProjectTypeSubmission/Target" />
				</xsl:when>
				<xsl:otherwise>
					<xsl:apply-templates select="ProjectType/ProjectTypeTopAdmin" />
				</xsl:otherwise>
				</xsl:choose>
			</table>
		</xsl:if>

		<xsl:if test="ProjectDescr/Publication != ''">
			<h3 class="overview_title">PUBLICATION</h3>
			<table class="overview_table">
				<xsl:apply-templates select="ProjectDescr/Publication" />
			</table>
		</xsl:if>
	</xsl:template>

	<xsl:template match="ProjectDescr/Title" >
		<tr><th>Project title</th><td><xsl:value-of select="." /></td></tr>
	</xsl:template>

	<xsl:template match="ProjectDescr/Description" >
		<tr><th>Description</th><td><xsl:value-of select="." /></td></tr>
	</xsl:template>

	<xsl:template match="ProjectDescr/ProjectReleaseDate" >
		<tr><td colspan="2"><h4>Data Release</h4></td></tr>
		<xsl:choose>
		<xsl:when test=". != ''">
			<tr><th style="color:red">Data Release</th><td sstyle="color:red"><xsl:value-of select="substring(., 1, 10)" /></td></tr>
		</xsl:when>
		<xsl:otherwise>
			<tr><th style="color:red">Data Release</th><td style="color:red">Hold</td></tr>
		</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="ProjectDescr/Relevance" >
		<xsl:if test="Agricultural != ''">
			<tr><th>Relevance</th><td>Agricultural</td></tr>
		</xsl:if>
		<xsl:if test="Medical != ''">
			<tr><th>Relevance</th><td>Medical</td></tr>
		</xsl:if>
		<xsl:if test="Industrial != ''">
			<tr><th>Relevance</th><td>Industrial</td></tr>
		</xsl:if>
		<xsl:if test="Environmental != ''">
			<tr><th>Relevance</th><td>Environmental</td></tr>
		</xsl:if>
		<xsl:if test="Evolution != ''">
			<tr><th>Relevance</th><td>Evolution</td></tr>
		</xsl:if>
		<xsl:if test="Evolution != ''">
			<tr><th>Relevance</th><td>Evolution</td></tr>
		</xsl:if>
		<xsl:if test="Other != ''">
			<tr><th>Relevance</th><td>Other</td></tr>
			<tr><th>Relevance description</th><td><xsl:value-of select="." /></td></tr>
		</xsl:if>
	</xsl:template>

	<xsl:template match="ProjectDescr/ExternalLink" >
		<xsl:for-each select=".">
			<tr><td colspan="2"><h4>External Link <xsl:number level="single" format="1" count="ExternalLink"/></h4></td></tr>
			<xsl:if test="@label != ''">
				<tr><th>Link description</th><td><xsl:value-of select="@label" /></td></tr>
			</xsl:if>
			<xsl:if test="./URL != ''">
				<tr><th>URL</th><td><a href="{./URL}" target="_blank"><xsl:value-of select="./URL" /></a></td></tr>
			</xsl:if>
		</xsl:for-each>
	</xsl:template>

	<xsl:template match="ProjectDescr/Grant" >
		<xsl:for-each select=".">
			<tr><td colspan="2"><h4>Grant <xsl:number level="single" format="1" count="Grant"/></h4></td></tr>
			<xsl:if test="./Agency != ''">
				<tr><th>Agency</th><td><xsl:value-of select="./Agency" /></td></tr>
			</xsl:if>
			<xsl:if test="./Agency/@abbr != ''">
				<tr><th>Agency abbreviation</th><td><xsl:value-of select="./Agency/@abbr" /></td></tr>
			</xsl:if>
			<xsl:if test="@GrantId != ''">
				<tr><th>Grant ID</th><td><xsl:value-of select="@GrantId" /></td></tr>
			</xsl:if>
			<xsl:if test="./Title != ''">
				<tr><th>Grant title</th><td><xsl:value-of select="./Title" /></td></tr>
			</xsl:if>
		</xsl:for-each>
	</xsl:template>

	<xsl:template match="ProjectType/ProjectTypeSubmission/ProjectDataTypeSet" >
		<tr><td colspan="2"><h4>Project data type</h4></td></tr>
		<tr><th>Project data type</th><td>
			<xsl:for-each select="DataType">
				<xsl:if test="position() != 1">, </xsl:if>
				<xsl:value-of select="." />
			</xsl:for-each>
		</td></tr>
	 </xsl:template>

	<xsl:template match="ProjectType/ProjectTypeSubmission" >
		<tr><td colspan="2"><h4>Sample scope/Material/Capture/Methodology</h4></td></tr>
		<tr><th>Sample scope</th><td><xsl:value-of select="substring(Target/@sample_scope, 2)" /></td></tr>
		<tr><th>Material</th><td><xsl:value-of select="substring(Target/@material, 2)" /></td></tr>
		<tr><th>Capture</th><td><xsl:value-of select="substring(Target/@capture, 2)" /></td></tr>
	</xsl:template>

	<xsl:template match="ProjectType/ProjectTypeSubmission/Method" >
		<tr><th>Methodology</th><td><xsl:value-of select="substring(@method_type, 2)" /></td></tr>
		<xsl:if test="@method_type = 'eOther'">
			<tr><th>Methodology description</th><td><xsl:value-of select="." /></td></tr>
		</xsl:if>
	</xsl:template>

	<xsl:template match="ProjectType/ProjectTypeSubmission/Objectives" >
		<tr><td colspan="2"><h4>Objective</h4></td></tr>
		<tr><th>Objective</th><td>
		<xsl:for-each select="Data">
			<xsl:if test="position() != 1">, </xsl:if>
			<xsl:value-of select="substring(@data_type, 2)" />
		</xsl:for-each>
		</td></tr>
	</xsl:template>

	<xsl:template match="ProjectDescr/LocusTagPrefix" >
		<xsl:if test=". != ''">
		<tr><td colspan="2"><h4>Locus tag prefix</h4></td></tr>
		<tr><th>Locus tag prefix</th><td><xsl:value-of select="." /></td></tr>
		</xsl:if>
	</xsl:template>

	<xsl:template match="ProjectType/ProjectTypeSubmission/Target" >
		<tr><td colspan="2"><h4>Organism information</h4></td></tr>
		<tr><th>Organism name</th><td><xsl:value-of select="Organism/OrganismName" /></td></tr>
		<xsl:if test="Organism/@taxID != '0'">
			<tr><th>Taxonomy ID</th><td><a href="http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id={Organism/@taxID}" target="_blank"><xsl:value-of select="Organism/@taxID" /></a></td></tr>
		</xsl:if>
		<xsl:if test="Organism/Strain != ''">
			<tr><th>Strain,breed,cultivar</th><td><xsl:value-of select="Organism/Strain" /></td></tr>
		</xsl:if>
		<xsl:if test="Organism/Label != ''">
			<tr><th>Isolate name or label</th><td><xsl:value-of select="Organism/Label" /></td></tr>
		</xsl:if>
		<xsl:if test="Description != ''">
			<tr><th>Description</th><td><xsl:value-of select="Description" /></td></tr>
		</xsl:if>
		<xsl:if test="(Organism/Organization != '') or (Organism/Reproduction != '') or (Organism/GenomeSize != '') or (Organism/RepliconSet/Ploidy/@type != '')">
			<tr><td colspan="2"><h4>General Properties</h4></td></tr>
			<xsl:if test="Organism/Organization != ''">
				<tr><th>Cellularity</th><td><xsl:value-of select="substring(Organism/Organization, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/Reproduction != ''">
				<tr><th>Reproduction</th><td><xsl:value-of select="substring(Organism/Reproduction, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/GenomeSize != ''">
				<tr><th>Haploid genome size</th><td><xsl:value-of select="Organism/GenomeSize" /><xsl:text> </xsl:text><xsl:value-of select="Organism/GenomeSize/@units" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/RepliconSet/Ploidy/@type != ''">
				<tr><th>Ploidy</th><td><xsl:value-of select="substring(Organism/RepliconSet/Ploidy/@type, 2)" /></td></tr>
			</xsl:if>
		</xsl:if>
		<xsl:for-each select="Organism/RepliconSet/Replicon">
			<tr><td colspan="2"><h4>Organism Replicon <xsl:number level="single" format="1" count="RepliconSet/Replicon"/></h4></td></tr>
			<xsl:if test="Name != ''">
				<tr><th>Name</th><td><xsl:value-of select="Name" /></td></tr>
			</xsl:if>
			<xsl:if test="Type != ''">
				<tr><th>Type</th><td><xsl:value-of select="substring(Type, 2)" /></td></tr>
				<xsl:if test="Type/@typeOtherDescr != ''">
					<tr><th>Type Description</th><td><xsl:value-of select="Type/@typeOtherDescr" /></td></tr>
				</xsl:if>
				<tr><th>Location</th><td><xsl:value-of select="substring(Type/@location, 2)" /></td></tr>
				<xsl:if test="Type/@locationOtherDescr != ''">
					<tr><th>Location Description</th><td><xsl:value-of select="Type/@locationOtherDescr" /></td></tr>
				</xsl:if>
			</xsl:if>
			<xsl:if test="Size != ''">
				<tr><th>Size</th><td><xsl:value-of select="Size" /><xsl:text> </xsl:text><xsl:value-of select="Size/@units" /></td></tr>
			</xsl:if>
			<xsl:if test="Description != ''">
				<tr><th>Description</th><td><xsl:value-of select="Description" /></td></tr>
			</xsl:if>
			<xsl:if test="@order != ''">
				<tr><th>Order</th><td><xsl:value-of select="@order" /></td></tr>
			</xsl:if>
		</xsl:for-each>
		<xsl:if test="Organism/BiologicalProperties/Phenotype != ''">
			<tr><td colspan="2"><h4>Phenotype</h4></td></tr>
			<xsl:if test="Organism/BiologicalProperties/Phenotype/Disease != ''">
				<tr><th>Disease</th><td><xsl:value-of select="Organism/BiologicalProperties/Phenotype/Disease" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Phenotype/BioticRelationship != ''">
				<tr><th>Biotic Relationship</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Phenotype/BioticRelationship, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Phenotype/TrophicLevel != ''">
				<tr><th>Trophic Level</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Phenotype/TrophicLevel, 2)" /></td></tr>
			</xsl:if>
		</xsl:if>
		<xsl:if test="Organism/BiologicalProperties/Morphology != ''">
			<tr><td colspan="2"><h4>Prokaryote Morphology</h4></td></tr>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Shape != ''">
				<tr><th>Shape</th><td>
					<xsl:for-each select="Organism/BiologicalProperties/Morphology/Shape">
						<xsl:if test="position() != 1">, </xsl:if>
						<xsl:value-of select="substring(., 2)" />
					</xsl:for-each>
				</td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Gram != ''">
				<tr><th>Gram</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Gram, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Motility != ''">
				<tr><th>Motility</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Motility, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Enveloped != ''">
				<tr><th>Enveloped</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Enveloped, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Endospores != ''">
				<tr><th>Endospores</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Endospores, 2)" /></td></tr>
			</xsl:if>
		</xsl:if>
		<xsl:if test="Organism/BiologicalProperties/Environment != ''">
			<tr><td colspan="2"><h4>Ecological Environment</h4></td></tr>
			<xsl:if test="Organism/BiologicalProperties/Environment/Habitat != ''">
				<tr><th>Habitat</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/Habitat, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/Salinity != ''">
				<tr><th>Salinity</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/Salinity, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/OxygenReq != ''">
				<tr><th>Oxygen requirement</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/OxygenReq, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/TemperatureRange != ''">
				<tr><th>Temperature range</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/TemperatureRange, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/OptimumTemperature != ''">
				<tr><th>Optimum Temperature</th><td><xsl:value-of select="Organism/BiologicalProperties/Environment/OptimumTemperature" /> Celsius</td></tr>
			</xsl:if>
		</xsl:if>
	</xsl:template>

	<xsl:template match="ProjectType/ProjectTypeTopAdmin" >
		<tr><td colspan="2"><h4>Organism information</h4></td></tr>
		<tr><th>Organism name</th><td><xsl:value-of select="Organism/OrganismName" /></td></tr>
		<xsl:if test="Organism/@taxID != '0'">
			<tr><th>Taxonomy ID</th><td><a href="http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id={Organism/@taxID}" target="_blank"><xsl:value-of select="Organism/@taxID" /></a></td></tr>
		</xsl:if>
		<xsl:if test="Organism/Strain != ''">
			<tr><th>Strain,breed,cultivar</th><td><xsl:value-of select="Organism/Strain" /></td></tr>
		</xsl:if>
		<xsl:if test="Organism/Label != ''">
			<tr><th>Isolate name or label</th><td><xsl:value-of select="Organism/Label" /></td></tr>
		</xsl:if>
		<xsl:if test="(Organism/Organization != '') or (Organism/Reproduction != '') or (Organism/GenomeSize != '') or (Organism/RepliconSet/Ploidy/@type != '')">
			<tr><td colspan="2"><h4>General Properties</h4></td></tr>
			<xsl:if test="Organism/Organization != ''">
				<tr><th>Cellularity</th><td><xsl:value-of select="substring(Organism/Organization, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/Reproduction != ''">
				<tr><th>Reproduction</th><td><xsl:value-of select="substring(Organism/Reproduction, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/GenomeSize != ''">
				<tr><th>Haploid genome size</th><td><xsl:value-of select="Organism/GenomeSize" /><xsl:text> </xsl:text><xsl:value-of select="Organism/GenomeSize/@units" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/RepliconSet/Ploidy/@type != ''">
				<tr><th>Ploidy</th><td><xsl:value-of select="substring(Organism/RepliconSet/Ploidy/@type, 2)" /></td></tr>
			</xsl:if>
		</xsl:if>
		<xsl:for-each select="Organism/RepliconSet/Replicon">
			<tr><td colspan="2"><h4>Organism Replicon <xsl:number level="single" format="1" count="RepliconSet/Replicon"/></h4></td></tr>
			<xsl:if test="Name != ''">
				<tr><th>Name</th><td><xsl:value-of select="Name" /></td></tr>
			</xsl:if>
			<xsl:if test="Type != ''">
				<tr><th>Type</th><td><xsl:value-of select="substring(Type, 2)" /></td></tr>
				<xsl:if test="Type/@typeOtherDescr != ''">
					<tr><th>Type Description</th><td><xsl:value-of select="Type/@typeOtherDescr" /></td></tr>
				</xsl:if>
				<tr><th>Location</th><td><xsl:value-of select="substring(Type/@location, 2)" /></td></tr>
				<xsl:if test="Type/@locationOtherDescr != ''">
					<tr><th>Location Description</th><td><xsl:value-of select="Type/@locationOtherDescr" /></td></tr>
				</xsl:if>
			</xsl:if>
			<xsl:if test="Size != ''">
				<tr><th>Size</th><td><xsl:value-of select="Size" /><xsl:text> </xsl:text><xsl:value-of select="Size/@units" /></td></tr>
			</xsl:if>
			<xsl:if test="Description != ''">
				<tr><th>Description</th><td><xsl:value-of select="Description" /></td></tr>
			</xsl:if>
			<xsl:if test="@order != ''">
				<tr><th>Order</th><td><xsl:value-of select="@order" /></td></tr>
			</xsl:if>
		</xsl:for-each>
		<xsl:if test="Organism/BiologicalProperties/Phenotype != ''">
			<tr><td colspan="2"><h4>Phenotype</h4></td></tr>
			<xsl:if test="Organism/BiologicalProperties/Phenotype/Disease != ''">
				<tr><th>Disease</th><td><xsl:value-of select="Organism/BiologicalProperties/Phenotype/Disease" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Phenotype/BioticRelationship != ''">
				<tr><th>Biotic Relationship</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Phenotype/BioticRelationship, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Phenotype/TrophicLevel != ''">
				<tr><th>Trophic Level</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Phenotype/TrophicLevel, 2)" /></td></tr>
			</xsl:if>
		</xsl:if>
		<xsl:if test="Organism/BiologicalProperties/Morphology != ''">
			<tr><td colspan="2"><h4>Prokaryote Morphology</h4></td></tr>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Shape != ''">
				<tr><th>Shape</th><td>
					<xsl:for-each select="Organism/BiologicalProperties/Morphology/Shape">
						<xsl:if test="position() != 1">, </xsl:if>
						<xsl:value-of select="substring(., 2)" />
					</xsl:for-each>
				</td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Gram != ''">
				<tr><th>Gram</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Gram, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Motility != ''">
				<tr><th>Motility</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Motility, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Enveloped != ''">
				<tr><th>Enveloped</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Enveloped, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Morphology/Endospores != ''">
				<tr><th>Endospores</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Morphology/Endospores, 2)" /></td></tr>
			</xsl:if>
		</xsl:if>
		<xsl:if test="Organism/BiologicalProperties/Environment != ''">
			<tr><td colspan="2"><h4>Ecological Environment</h4></td></tr>
			<xsl:if test="Organism/BiologicalProperties/Environment/Habitat != ''">
				<tr><th>Habitat</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/Habitat, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/Salinity != ''">
				<tr><th>Salinity</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/Salinity, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/OxygenReq != ''">
				<tr><th>Oxygen requirement</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/OxygenReq, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/TemperatureRange != ''">
				<tr><th>Temperature range</th><td><xsl:value-of select="substring(Organism/BiologicalProperties/Environment/TemperatureRange, 2)" /></td></tr>
			</xsl:if>
			<xsl:if test="Organism/BiologicalProperties/Environment/OptimumTemperature != ''">
				<tr><th>Optimum Temperature</th><td><xsl:value-of select="Organism/BiologicalProperties/Environment/OptimumTemperature" /> Celsius</td></tr>
			</xsl:if>
		</xsl:if>
	</xsl:template>

	<xsl:template match="ProjectDescr/Publication" >
		<xsl:for-each select=".">
			<tr><td colspan="2"><h4>Publication <xsl:number level="single" format="1" count="Publication"/></h4></td></tr>
			<xsl:if test="./DbType = 'ePubmed'">
				<tr><th>PubMed ID</th><td><a href="http://www.ncbi.nlm.nih.gov/pubmed/{./@id}" target="_blank"><xsl:value-of select="./@id" /></a></td></tr>
			</xsl:if>
			<xsl:if test="./DbType = 'eDOI'">
				<tr><th>DOI</th><td><xsl:value-of select="./@id" /></td></tr>
			</xsl:if>
		</xsl:for-each>
	</xsl:template>

</xsl:stylesheet>
