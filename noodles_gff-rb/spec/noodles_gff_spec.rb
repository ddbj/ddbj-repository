RSpec.describe NoodlesGFF do
  example 'empty' do
    NoodlesGFF.parse ''
  end

  example 'valid' do
    NoodlesGFF.parse <<~GFF
      ##gff-version 3
      ##sequence-region chr1 1 30584173
      chr1	feature	gene	1	1967	.	-	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
      chr1	feature	rRNA	1	1967	.	-	.	ID=Mp1g00005a.1;Name=Mp1g00005a.1;Parent=Mp1g00005a;note=partial;product=26S ribosomal RNA
      chr1	feature	exon	1	1967	.	-	.	ID=Mp1g00005a.1.exon1;Name=Mp1g00005a.1.exon1;Parent=Mp1g00005a.1;note=partial
      ##FASTA
      >chr1
      AGCAAGGCTACTCTGCCGCTTACAATACTCGTCCCATATTTAAGTCGTCTGCAAAGGATT
      CATCTCCCCGATCGTTTGGAATTGCGATTCAAAGCACCCGGGCACAGCTTCTTCCGCCGG
      CCCGGGGAAACTCTCGACACATGCTTCTGGGGACGGACGAGCCGCCCCTACCGGTAGTCG
    GFF
  end

  example 'start is invalid' do
    expect {
      NoodlesGFF.parse <<~GFF
        chr1	feature	gene	foo	1967	.	-	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
      GFF
    }.to raise_error(NoodlesGFF::Error, 'Line 1: Custom { kind: InvalidData, error: InvalidDigit(0) }')
  end

  example 'end is invalid' do
    expect {
      NoodlesGFF.parse <<~GFF
        chr1	feature	gene	1	foo	.	-	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
      GFF
    }.to raise_error(NoodlesGFF::Error, 'Line 1: Custom { kind: InvalidData, error: InvalidDigit(0) }')
  end

  example 'score is invalid' do
    expect {
      NoodlesGFF.parse <<~GFF
        chr1	feature	gene	1	1967	foo	-	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
      GFF
    }.to raise_error(NoodlesGFF::Error, 'Line 1: Custom { kind: InvalidData, error: InvalidDigit(0) }')
  end

  example 'strand is invalid' do
    expect {
      NoodlesGFF.parse <<~GFF
        chr1	feature	gene	1	1967	.	foo	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
      GFF
    }.to raise_error(NoodlesGFF::Error, 'Line 1: Custom { kind: InvalidData, error: "invalid strand" }')
  end

  example 'phase is invalid' do
    expect {
      NoodlesGFF.parse <<~GFF
        chr1	feature	gene	1	1967	.	-	foo	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
      GFF
    }.to raise_error(NoodlesGFF::Error, 'Line 1: Custom { kind: InvalidData, error: "invalid phase" }')
  end

  example 'attributes is invalid' do
    expect {
      NoodlesGFF.parse <<~GFF
        chr1	feature	gene	1	1967	.	-	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial;foo
      GFF
    }.to raise_error(NoodlesGFF::Error, 'Line 1: Custom { kind: InvalidData, error: "invalid tag" }')
  end
end
