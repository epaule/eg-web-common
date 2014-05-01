=head1 LICENSE

Copyright [2009-2014] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::EnsEMBL::GlyphSet::_flat_file;

use strict;

use List::Util qw(reduce);

use EnsEMBL::Web::Text::FeatureParser;
use EnsEMBL::Web::TmpFile::Text;
use EnsEMBL::Web::Tools::Misc;

use Bio::EnsEMBL::Variation::Utils::Constants;

use base qw(Bio::EnsEMBL::GlyphSet::_alignment Bio::EnsEMBL::GlyphSet_wiggle_and_block);

sub features {
  my $self         = shift;
  my $container    = $self->{'container'};
  my $species_defs = $self->species_defs;
  my $sub_type     = $self->my_config('sub_type');
  my $parser       = EnsEMBL::Web::Text::FeatureParser->new($species_defs);
  my $features     = [];
  my %results;
  
  $self->{'_default_colour'} = $self->SUPER::my_colour($sub_type);
  
  $parser->filter($container->seq_region_name, $container->start, $container->end);
  
  $self->{'parser'} = $parser;
 
  my $data; 
  if ($sub_type eq 'url') {
    my $response = EnsEMBL::Web::Tools::Misc::get_url_content($self->my_config('url'));
    
    if ($data = $response->{'content'}) {
      $parser->parse($data, $self->my_config('format'));
    } else {
      warn "!!! $response->{'error'}";
    }
  } else {
    my $file = EnsEMBL::Web::TmpFile::Text->new(filename => $self->my_config('file'));
    
    return $self->errorTrack(sprintf 'The file %s could not be found', $self->my_config('caption')) if !$file->exists && $self->strand < 0;

    $data = $file->retrieve;
    
    return [] unless $data;

    $parser->parse($data, $self->my_config('format'));
  }

  # if no tracks found, filter by synonym name
  unless ($parser->{'tracs'}){

    my $synonym_obj = $container->get_all_synonyms(); # arrayref of Bio::EnsEMBL::SeqRegionSynonym objects
    my $features;

    foreach my $synonym (@$synonym_obj) {
      $parser->filter($synonym->name, $container->start, $container->end);
      $parser->parse($data, $self->my_config('format'));
      last if $parser->{'tracs'};
    }
  }
 
  ## Now we translate all the features to their rightful co-ordinates
  while (my ($key, $T) = each (%{$parser->{'tracks'}})) {
    $_->map($container) for @{$T->{'features'}};
  
    ## Set track depth a bit higher if there are lots of user features
    $T->{'config'}{'dep'} = scalar @{$T->{'features'}} > 20 ? 20 : scalar @{$T->{'features'}};

    ### ensure the display of the VEP features using colours corresponding to their consequence
    if ($self->my_config('format') eq 'VEP_OUTPUT') {
      my %overlap_cons = %Bio::EnsEMBL::Variation::Utils::Constants::OVERLAP_CONSEQUENCES;      
      my %cons_lookup = map { $overlap_cons{$_}{'SO_term'} => $overlap_cons{$_}{'rank'} } keys %overlap_cons;
    
      ## Group results into sets by start, end and allele, so we can treat them 
      ## as single features in the next step 
      my %cons = map { # lowest rank consequence from comma-list
        $_->consequence => reduce { $cons_lookup{$a} < $cons_lookup{$b} ? $a : $b } split(/,/,$_->consequence); 
      } @{$T->{'features'}};
      @{$T->{'features'}} = sort {$a->start <=> $b->start
          || $a->end <=> $b->end
          || $a->allele_string cmp $b->allele_string
          || $cons_lookup{$cons{$a->consequence}} <=> $cons_lookup{$cons{$b->consequence}}
        } @{$T->{'features'}};

      my $colours = $species_defs->colour('variation');
      
      $T->{'config'}{'itemRgb'} = 'on';
    
      ## Merge raw features into a set of unique variants with multiple consequences 
      my ($start, $end, $allele);
      foreach (@{$T->{'features'}}) {
        my $last = $features->[-1];
        if ($last && $last->start == $_->start && $last->end == $_->end && $last->allele_string eq $_->allele_string) {
          push @{$last->external_data->{'Type'}[0]}, $_->consequence;
        }
        else {
          $_->external_data->{'item_colour'}[0] = $colours->{lc $cons{$_->consequence}}->{'default'} || $colours->{'default'}->{'default'};
          $_->external_data->{'Type'}[0]        = [$_->consequence];
          push @$features, $_;
          $start = $_->start;
          $end = $_->end;
          $allele = $_->allele_string;
        }
      }
      ## FinallY dedupe the consequences
      foreach (@$features) {
        my %dedupe;
        foreach my $c (@{$_->external_data->{'Type'}[0]||[]}) {
          $dedupe{$c}++;
        }
        $_->external_data->{'Type'}[0] = join(', ', sort {$cons_lookup{$a} <=> $cons_lookup{$b}} keys %dedupe);
      }
    }
    else {
      $features = $T->{'features'};
    }

    $results{$key} = [$features, $T->{'config'}];
  }
  
  return %results;

  warn Dumper(\%results);
}


## EG gradient

sub render_gradient {
  my $self = shift;
  
  $self->{'renderer_no_join'} = 1;
  $self->{'legend'}{'gradient_legend'} = 1; # instruct to draw legend  
  $self->SUPER::render_normal(8, 0);
  
  # Add text line showing name and score range
  
  my %features = $self->features;
  my $fconf    = $features{url}->[1];
  my $label    = sprintf '%s  %.2f - %.2f', $self->my_config('name'), $fconf->{min_score}, $fconf->{max_score};
  my %font     = $self->get_font_details('innertext', 1);
  
  my (undef, undef, $width, $height) = $self->get_text_width(0,  $label, '', %font); 
  
  $self->push($self->Text({
    text      => $label,
    width     => $width,
    halign    => 'left',
    valign    => 'bottom',
    colour    => $self->my_config('colour'),
    y         => 7,
    height    => $height,
    x         => 1,
    absolutey => 1,
    absolutex => 1,
    %font,
  })); 
}

sub href {
  return ''; # this causes the zmenu content to be supressed (leaving only title)
}

sub feature_title {
  my ($self, $f) = @_;
  return sprintf '%.2f', $f->score; # the score is all that we want to show
}

sub feature_group {
  my ($self, $f) = @_;
  my $name = '';
  if ($f->can('hseqname')) {
    ($name = $f->hseqname) =~ s/(\..*|T7|SP6)$//; # this regexp will remove the differences in names between the ends of BACs/FOSmids.
  }
  return $name;
}

## EG /gradient


1;
